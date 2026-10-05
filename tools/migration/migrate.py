#!/usr/bin/env python3
"""Read-only Supabase export, guarded staging restore, and independent verification.

No network or database command runs without --execute. No source mutation is implemented.
Credentials are read by libpq from private service/password files and are never CLI arguments.
"""
from __future__ import annotations

import argparse
import contextvars
import functools
import contextlib
import hashlib
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import sys
import tempfile
import uuid
from datetime import datetime, timezone
from urllib import error, parse, request

VERSION = 1
DIAGNOSTIC_DIRECTORY = contextvars.ContextVar("migration_diagnostic_directory", default=None)
SERVICE = re.compile(r"^[A-Za-z0-9_.-]+$")
SNAPSHOT = re.compile(r"^[0-9A-Fa-f]+-[0-9A-Fa-f]+-[0-9]+$")
USER_SCHEMAS = "n.nspname NOT LIKE 'pg_%' AND n.nspname <> 'information_schema'"
CATALOG_SQL = f"""SELECT json_build_object(
 'server_version_num', current_setting('server_version_num')::int,
 'database', current_database(),
 'tables', COALESCE((SELECT json_agg(json_build_object('schema', n.nspname,
 'table', c.relname) ORDER BY n.nspname,c.relname) FROM pg_class c JOIN
 pg_namespace n ON n.oid=c.relnamespace WHERE c.relkind IN ('r','p','m')
 AND {USER_SCHEMAS}), '[]'::json),
 'foreign_tables', (SELECT count(*) FROM pg_class c JOIN pg_namespace n
 ON n.oid=c.relnamespace WHERE c.relkind='f' AND {USER_SCHEMAS}),
 'sequences', COALESCE((SELECT json_agg(json_build_object('schema',schemaname,
 'name',sequencename,'start',start_value,'min',min_value,'max',max_value,
 'increment',increment_by,'cycle',cycle,'cache',cache_size,'last_value',last_value)
 ORDER BY schemaname,sequencename) FROM pg_sequences
 WHERE schemaname NOT LIKE 'pg_%' AND schemaname <> 'information_schema'),'[]'::json),
 'extensions', (SELECT json_agg(json_build_object('name',extname,'version',extversion))
 FROM pg_extension),
 'roles', (SELECT json_agg(json_build_object('name',rolname,'login',rolcanlogin,
 'superuser',rolsuper,'bypass_rls',rolbypassrls)) FROM pg_roles)
)::text;"""
STORAGE_SQL = """SELECT json_build_object(
 'buckets', COALESCE((SELECT json_agg(to_jsonb(b)) FROM storage.buckets b),'[]'::json),
 'objects', COALESCE((SELECT json_agg(to_jsonb(o) ORDER BY bucket_id,name)
 FROM storage.objects o),'[]'::json))::text;"""


class MigrationError(Exception):
    pass


def now():
    return datetime.now(timezone.utc).isoformat()


def private_file(value: str, label: str) -> Path:
    path = Path(value).expanduser()
    if not path.is_file() or path.is_symlink():
        raise MigrationError(f"{label} must be an existing regular private file.")
    if path.stat().st_mode & 0o077:
        raise MigrationError(f"{label} permissions must be 600 or stricter.")
    return path.resolve()


def outside_repository(path: Path):
    resolved = path.resolve()
    if any((parent / ".git").exists() for parent in [resolved, *resolved.parents]):
        raise MigrationError("Private data/output must be outside any Git checkout.")
    return resolved


def service_name(value: str):
    if not SERVICE.fullmatch(value or ""):
        raise MigrationError("Use a simple libpq service alias, not a connection URL.")
    return value


def db_env(read_only=True):
    env = dict(os.environ)
    for label in ("PGSERVICEFILE", "PGPASSFILE"):
        if not env.get(label):
            raise MigrationError(f"Set {label} to a private file outside the repository.")
        env[label] = str(outside_repository(private_file(env[label], label)))
    # Ignore ambient credentials/host selection; a validated service alias is explicit.
    for label in ("PGPASSWORD", "PGHOST", "PGHOSTADDR", "PGPORT", "PGUSER", "PGDATABASE", "PGSERVICE"):
        env.pop(label, None)
    env["PGOPTIONS"] = (
        "-c default_transaction_read_only=on -c timezone=UTC -c row_security=off"
        if read_only else "-c timezone=UTC -c row_security=off"
    )
    env["PGCONNECT_TIMEOUT"] = "15"
    return env


def binary(name):
    path = shutil.which(name)
    if not path:
        raise MigrationError(f"Install PostgreSQL client utility {name}. No data copied.")
    return path


def with_diagnostics(operation):
    @functools.wraps(operation)
    def wrapped(args):
        directory = outside_repository(Path(args.output).expanduser())
        token = DIAGNOSTIC_DIRECTORY.set(directory)
        try:
            return operation(args)
        finally:
            DIAGNOSTIC_DIRECTORY.reset(token)
    return wrapped


def private_diagnostic(stderr, output=None):
    directory = DIAGNOSTIC_DIRECTORY.get()
    if output is None and directory is not None:
        output = directory / f"diagnostic-{uuid.uuid4().hex}.log"
    if output is None:
        return ""
    # A diagnostic can contain Auth hashes or private SQL rows. Never log to a
    # repository, non-private directory, symlink, or console.
    try:
        if output.is_symlink() or not output.parent.is_dir() or output.parent.stat().st_mode & 0o077:
            return ""
        outside_repository(output)
        write_text(output, stderr)
    except (OSError, MigrationError):
        return ""
    return f" Details are in private file {output.name}."


def database_error_reason(stderr):
    error = stderr.lower()
    if "password authentication failed" in error or "no password supplied" in error:
        return "Authentication failed; check the private service/passfile."
    if "permission denied" in error or "row-level security" in error:
        return "Database access denied (permissions/RLS); no data was silently omitted."
    if "invalid snapshot" in error or "snapshot identifier" in error:
        return "Snapshot failed; use a direct connection or session pooler."
    if "could not connect" in error or "connection to server" in error or "timeout expired" in error:
        return "Database connection failed; check host/network/private service configuration."
    return "Database command failed; no success recorded."


def command(args, env=None, sql=None, output: Path | None = None):
    """Suppress command stderr: database errors can contain personal data."""
    try:
        result = subprocess.run(args, env=env, input=sql, text=True,
                                stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                                timeout=3600, check=False)
    except (OSError, subprocess.TimeoutExpired):
        raise MigrationError(f"{Path(args[0]).name} could not complete; no success recorded.") from None
    if result.returncode:
        suffix = private_diagnostic(result.stderr, output)
        raise MigrationError(database_error_reason(result.stderr) + suffix)
    return result.stdout


def psql_args(service):
    return [binary("psql"), "--no-psqlrc", "--no-password", "-qAt",
            "--set=ON_ERROR_STOP=1", f"--dbname=service={service_name(service)}"]


def sql_literal(text):
    return "'" + text.replace("'", "''") + "'"


def identifier(text):
    return '"' + text.replace('"', '""') + '"'


def transaction_sql(sql, snapshot=None):
    imported = f"SET TRANSACTION SNAPSHOT {sql_literal(snapshot)};\n" if snapshot else ""
    return "BEGIN ISOLATION LEVEL REPEATABLE READ READ ONLY;\n" + imported + sql + "\nCOMMIT;\n"


def query(service, sql, snapshot=None):
    result = command(psql_args(service), db_env(), transaction_sql(sql, snapshot))
    try:
        return json.loads(result)
    except json.JSONDecodeError:
        raise MigrationError("Database response was not valid JSON; export is incomplete.") from None


def write_text(path, value):
    with open(path, "x", encoding="utf-8") as handle:
        os.chmod(path, 0o600)
        handle.write(value)


def write_json(path, value):
    write_text(path, json.dumps(value, indent=2, ensure_ascii=False) + "\n")


def file_hash(path):
    digest = hashlib.sha256()
    with open(path, "rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


@contextlib.contextmanager
def snapshot_session(service):
    """Keep an exported snapshot alive until dump, inventory and digests finish."""
    with tempfile.TemporaryFile(mode="w+t") as stderr:
        proc = subprocess.Popen(psql_args(service), env=db_env(), stdin=subprocess.PIPE,
                                stdout=subprocess.PIPE, stderr=stderr, text=True, bufsize=1)
        try:
            proc.stdin.write("BEGIN ISOLATION LEVEL REPEATABLE READ READ ONLY;\n"
                             "SELECT pg_export_snapshot();\n")
            proc.stdin.flush()
            snapshot = proc.stdout.readline().strip()
            if not SNAPSHOT.fullmatch(snapshot):
                stderr.seek(0)
                details = stderr.read()
                suffix = private_diagnostic(details)
                raise MigrationError("Could not establish a consistent read-only snapshot. "
                                     + database_error_reason(details) + suffix)
            yield snapshot
        finally:
            if proc.poll() is None:
                try:
                    proc.stdin.write("ROLLBACK;\n\\q\n")
                    proc.stdin.flush()
                    proc.wait(timeout=15)
                except (BrokenPipeError, subprocess.TimeoutExpired):
                    proc.kill()
                    proc.wait()
            if proc.stdin:
                proc.stdin.close()
            if proc.stdout:
                proc.stdout.close()


def table_digest(service, table, snapshot):
    # One canonical JSON row per line, sorted server-side for order-independent equality.
    # This can sort large tables: run the final export in a write-free maintenance window.
    qualified = identifier(table["schema"]) + "." + identifier(table["table"])
    sql = f"COPY (SELECT to_jsonb(t)::text FROM {qualified} t " \
          "ORDER BY to_jsonb(t)::text COLLATE \"C\") TO STDOUT;"
    digest = hashlib.sha256()
    rows = 0
    with tempfile.TemporaryFile() as stderr:
        proc = subprocess.Popen(psql_args(service), env=db_env(), stdin=subprocess.PIPE,
                                stdout=subprocess.PIPE, stderr=stderr)
        try:
            proc.stdin.write(transaction_sql(sql, snapshot).encode())
            proc.stdin.close()
            for line in proc.stdout:
                digest.update(line)
                rows += 1
            if proc.wait() != 0:
                stderr.seek(0)
                details = stderr.read().decode("utf-8", errors="replace")
                raise MigrationError("Table digest failed. " + database_error_reason(details)
                                     + private_diagnostic(details))
        finally:
            if proc.poll() is None:
                proc.kill()
                proc.wait()
            proc.stdout.close()
    return {**table, "rows": rows, "sha256_sorted_json": digest.hexdigest()}


@with_diagnostics
def export_database(args):
    out = outside_repository(Path(args.output).expanduser())
    if out.exists():
        raise MigrationError("Use a new export directory; existing exports are never overwritten.")
    for name in ("psql", "pg_dump", "pg_restore", "pg_dumpall"):
        binary(name)
    db_env()
    out.mkdir(parents=True, mode=0o700)
    source = service_name(args.source)
    archive = out / "database.dump"
    with snapshot_session(source) as snapshot:
        catalog = query(source, CATALOG_SQL, snapshot)
        if catalog.get("foreign_tables", 0):
            raise MigrationError("Foreign tables need an explicit external-data export plan; full export refused.")
        required = {("public", "profiles"), ("auth", "users"), ("auth", "identities"),
                    ("storage", "buckets"), ("storage", "objects")}
        available = {(t["schema"], t["table"]) for t in catalog["tables"]}
        if not required.issubset(available):
            raise MigrationError("Expected Night Owl/auth/storage tables are missing; export not complete.")
        command([binary("pg_dump"), f"--dbname=service={source}", "--format=custom",
                 "--no-password", "--large-objects",
                 f"--snapshot={snapshot}", f"--file={archive}"], db_env(),
                output=out / "dump-error.log")
        os.chmod(archive, 0o600)
        # pg_dump normally omits extension-owned tables except extension configuration data.
        # Explicit table selection preserves every inventoried non-system table as a separate
        # rescue archive. Do not blindly replay it over a populated full restore.
        table_data = out / "all-table-data.dump"
        table_args = [f"--table={identifier(t['schema'])}.{identifier(t['table'])}"
                      for t in catalog["tables"]]
        command([binary("pg_dump"), f"--dbname=service={source}", "--format=custom",
                 "--data-only", "--large-objects", "--no-password",
                 f"--snapshot={snapshot}", f"--file={table_data}", *table_args], db_env(),
                output=out / "table-data-error.log")
        os.chmod(table_data, 0o600)
        toc = command([binary("pg_restore"), "--list", str(archive)])
        write_text(out / "archive-toc.txt", toc)
        storage = query(source, STORAGE_SQL, snapshot)
        write_json(out / "storage-index.json", storage)
        tables = [table_digest(source, table, snapshot) for table in catalog["tables"]]
        large_objects = table_digest(source, {"schema": "pg_catalog", "table": "pg_largeobject"}, snapshot)
    # Global roles cannot share a database snapshot; source writes must be frozen at cutover.
    roles = command([binary("pg_dumpall"), f"--dbname=service={source}",
                     f"--database={catalog['database']}", "--roles-only", "--no-role-passwords", "--no-password"], db_env(),
                    output=out / "roles-error.log")
    write_text(out / "roles.sql", roles)
    write_json(out / "manifest.json", {
        "format_version": VERSION, "created_at": now(), "status": "database_export_complete",
        "source_service": source, "server_version_num": catalog["server_version_num"],
        "source_database": catalog["database"], "extensions": catalog["extensions"],
        "roles": catalog["roles"], "tables": tables, "sequences": catalog["sequences"],
        "large_objects": large_objects, "full_database_archive": True,
        "scope": "Full logical archive plus explicit rescue archive of every inventoried non-system table; global role definitions without passwords.",
        "files": [{"path": p.name, "bytes": p.stat().st_size, "sha256": file_hash(p)}
                  for p in (archive, table_data, out / "archive-toc.txt", out / "storage-index.json", out / "roles.sql")],
        "storage_bytes": "not_exported", "platform_configuration": "manual_inventory_required",
    })
    print(f"Database archive complete: {len(tables)} tables. Storage bytes are still pending.")


def load_manifest(directory):
    out = outside_repository(Path(directory).expanduser())
    try:
        manifest = json.loads((out / "manifest.json").read_text())
        if manifest["format_version"] != VERSION or manifest["status"] != "database_export_complete":
            raise MigrationError("Unsupported/incomplete database manifest.")
        for item in manifest["files"]:
            path = artifact_path(out, item["path"])
            if path.stat().st_size != item["bytes"] or file_hash(path) != item["sha256"]:
                raise MigrationError("Archive checksum/size mismatch; restore refused.")
    except (OSError, KeyError, ValueError):
        raise MigrationError("Cannot verify archive manifest; restore refused.") from None
    return out, manifest


def artifact_path(base, relative):
    path = base / relative
    if Path(relative).is_absolute() or ".." in Path(relative).parts:
        raise MigrationError("Manifest contains an unsafe path.")
    if path.is_symlink() or not path.is_file() or not path.resolve().is_relative_to(base.resolve()):
        raise MigrationError("Manifest artifact must be a regular file inside the export directory.")
    return path


def validate_target(source, target, expected_database):
    source, target = service_name(source), service_name(target)
    if source == target:
        raise MigrationError("Source and target service aliases must differ.")
    if not expected_database:
        raise MigrationError("Set the independent exact target database name.")
    # Check endpoint + DB identity independently to catch two aliases for the same source.
    sql = """SELECT json_build_object('database',current_database(),
      'address',inet_server_addr()::text,'port',inet_server_port())::text;"""
    source_identity, target_identity = query(source, sql), query(target, sql)
    if source_identity == target_identity:
        raise MigrationError("Target resolves to the source database; restore refused.")
    if target_identity["database"] != expected_database:
        raise MigrationError("Connected target database does not match the declared staging database.")
    catalog = query(target, CATALOG_SQL)
    if catalog["tables"]:
        raise MigrationError("Target must have no non-system tables; no overwrite/drop is allowed.")
    return catalog


@with_diagnostics
def restore_database(args):
    out, manifest = load_manifest(args.output)
    target = service_name(args.target)
    catalog = validate_target(args.source, target, args.target_database)
    if catalog["server_version_num"] // 10000 < manifest["server_version_num"] // 10000:
        raise MigrationError("Target PostgreSQL major version is older than source.")
    # Do not apply privileged source roles.sql automatically. Target operator prepares reviewed
    # compatibility roles/extensions. Any missing dependency causes transaction rollback.
    command([binary("pg_restore"), f"--dbname=service={target}", "--no-password",
             "--no-owner", "--no-acl", "--single-transaction", "--exit-on-error",
             str(out / "database.dump")], db_env(read_only=False),
            output=out / f"restore-error-{datetime.now(timezone.utc).strftime('%Y%m%dT%H%M%S%f')}.log")
    print("Archive restored to empty staging database. Independent verification is still required.")


def compare_tables(expected, actual):
    expected_by_key = {(t["schema"], t["table"]): t for t in expected}
    actual_by_key = {(t["schema"], t["table"]): t for t in actual}
    return {
        "missing": sorted(set(expected_by_key) - set(actual_by_key)),
        "unexpected": sorted(set(actual_by_key) - set(expected_by_key)),
        "different": sorted(key for key in set(expected_by_key) & set(actual_by_key)
                            if expected_by_key[key]["rows"] != actual_by_key[key]["rows"]
                            or expected_by_key[key]["sha256_sorted_json"] != actual_by_key[key]["sha256_sorted_json"])
    }


@with_diagnostics
def verify_database(args):
    _, manifest = load_manifest(args.output)
    target = service_name(args.target)
    if source_service := manifest.get("source_service"):
        if target == source_service:
            raise MigrationError("Verification target must differ from source.")
    with snapshot_session(target) as snapshot:
        catalog = query(target, CATALOG_SQL, snapshot)
        if catalog["database"] != args.target_database:
            raise MigrationError("Target database name mismatch.")
        actual = [table_digest(target, table, snapshot) for table in catalog["tables"]]
        large_objects = table_digest(target, {"schema": "pg_catalog", "table": "pg_largeobject"}, snapshot)
    if catalog["sequences"] != manifest.get("sequences"):
        raise MigrationError("Sequence state mismatch; no cutover.")
    if large_objects != manifest.get("large_objects"):
        raise MigrationError("PostgreSQL large-object page checksum/count mismatch; no cutover.")
    differences = compare_tables(manifest["tables"], actual)
    if any(differences.values()):
        raise MigrationError(f"Data verification failed: {len(differences['missing'])} missing, "
                             f"{len(differences['unexpected'])} unexpected, "
                             f"{len(differences['different'])} changed tables. No cutover.")
    print(f"Database rows/digests match for {len(actual)} tables. Verify services and storage separately.")


class NoRedirect(request.HTTPRedirectHandler):
    def redirect_request(self, req, fp, code, msg, headers, newurl):
        return None


def storage_base(value):
    url = parse.urlsplit(value)
    if (url.scheme != "https" or not url.hostname or url.username or url.password
            or url.query or url.fragment or url.path not in ("", "/")):
        raise MigrationError("Source storage URL must be an HTTPS origin without credentials/query/path.")
    return value.rstrip("/")


def object_file(bucket, name):
    # Content identity is independent of untrusted object names; no path traversal.
    return "objects/" + hashlib.sha256(json.dumps([bucket, name], ensure_ascii=False).encode()).hexdigest()


def download_object(opener, url, key, target):
    req = request.Request(url, headers={"Authorization": "Bearer " + key, "apikey": key})
    digest, size = hashlib.sha256(), 0
    try:
        with opener.open(req, timeout=60) as response, open(target, "xb") as output:
            os.chmod(target, 0o600)
            for chunk in iter(lambda: response.read(1024 * 1024), b""):
                size += len(chunk)
                digest.update(chunk)
                output.write(chunk)
    except error.HTTPError as http_error:
        http_error.close()
        raise MigrationError("Storage download failed; no completed manifest/cutover.") from None
    except (error.URLError, OSError):
        # The URL/key/error details are deliberately excluded from console output.
        raise MigrationError("Storage download failed; no completed manifest/cutover.") from None
    return size, digest.hexdigest()


@with_diagnostics
def export_storage(args):
    out, _ = load_manifest(args.output)
    base = storage_base(args.storage_url)
    keyfile = outside_repository(private_file(args.storage_key_file, "Storage key file"))
    key = keyfile.read_text().strip()
    if not key or any(character.isspace() for character in key):
        raise MigrationError("Storage key file must contain one non-empty key.")
    storage = json.loads((out / "storage-index.json").read_text())
    destination = out / "storage"
    if destination.exists():
        raise MigrationError("Storage export already exists; use a new full export directory.")
    (destination / "objects").mkdir(parents=True, mode=0o700)
    os.chmod(destination, 0o700)
    opener = request.build_opener(NoRedirect())
    objects, seen = [], set()
    for obj in storage["objects"]:
        bucket, name = obj["bucket_id"], obj["name"]
        if not isinstance(bucket, str) or not isinstance(name, str) or not bucket or not name:
            raise MigrationError("Storage index contains an invalid object identity.")
        identity = bucket, name
        if identity in seen:
            raise MigrationError("Duplicate storage object identity.")
        seen.add(identity)
        relative = object_file(bucket, name)
        url = base + "/storage/v1/object/" + parse.quote(bucket, safe="") + "/" + parse.quote(name, safe="/")
        size, digest = download_object(opener, url, key, destination / relative)
        # Metadata size can be stale, but mismatch means no complete migration claim.
        expected_size = (obj.get("metadata") or {}).get("size")
        if expected_size is not None and str(expected_size) != str(size):
            raise MigrationError("Storage object byte size changed since database snapshot; repeat frozen export.")
        objects.append({"bucket": bucket, "name": name, "object_id": obj.get("id"),
                        "path": relative, "bytes": size, "sha256": digest})
    write_json(destination / "manifest.json", {
        "format_version": VERSION, "status": "storage_export_complete", "created_at": now(),
        "index_sha256": file_hash(out / "storage-index.json"),
        "objects": objects, "object_count": len(objects),
        "total_bytes": sum(obj["bytes"] for obj in objects),
        "consistency": "Requires source storage/database writes frozen for the whole export.",
    })
    print(f"Storage export complete: {len(objects)} objects. No files uploaded to a destination.")


@with_diagnostics
def verify_storage(args):
    out, _ = load_manifest(args.output)
    folder = out / "storage"
    try:
        manifest = json.loads((folder / "manifest.json").read_text())
        index = json.loads((out / "storage-index.json").read_text())
        if manifest["status"] != "storage_export_complete" or manifest["format_version"] != VERSION:
            raise MigrationError("Unsupported/incomplete storage manifest.")
        if manifest["index_sha256"] != file_hash(out / "storage-index.json"):
            raise MigrationError("Storage metadata checksum differs from the export manifest.")
        expected = {(item["bucket_id"], item["name"]) for item in index["objects"]}
        actual = {(item["bucket"], item["name"]) for item in manifest["objects"]}
        if expected != actual or len(manifest["objects"]) != len(expected):
            raise MigrationError("Storage identity/count mismatch.")
        for item in manifest["objects"]:
            path = artifact_path(folder, item["path"])
            if path.stat().st_size != item["bytes"] or file_hash(path) != item["sha256"]:
                raise MigrationError("Storage file checksum/size mismatch.")
        if manifest["object_count"] != len(actual) or manifest["total_bytes"] != sum(item["bytes"] for item in manifest["objects"]):
            raise MigrationError("Storage manifest totals are inconsistent.")
    except (OSError, KeyError, ValueError):
        raise MigrationError("Cannot verify storage manifest/files.") from None
    print(f"Local storage archive verified: {len(actual)} objects. Destination upload is not verified.")


def parser():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument("action", choices=["export-db", "export-storage", "restore-db", "verify-db", "verify-storage"])
    p.add_argument("--execute", action="store_true", help="Actually run the selected operation; default is offline plan only.")
    p.add_argument("--output", default=os.environ.get("NIGHTOWL_EXPORT_DIR", ""))
    p.add_argument("--source", default=os.environ.get("NIGHTOWL_SOURCE_SERVICE", ""))
    p.add_argument("--target", default=os.environ.get("NIGHTOWL_TARGET_SERVICE", ""))
    p.add_argument("--target-database", default=os.environ.get("NIGHTOWL_TARGET_DATABASE", ""))
    p.add_argument("--storage-url", default=os.environ.get("NIGHTOWL_SUPABASE_URL", ""))
    p.add_argument("--storage-key-file", default=os.environ.get("NIGHTOWL_STORAGE_KEY_FILE", ""))
    return p


def main(argv=None):
    args = parser().parse_args(argv)
    if not args.execute:
        print(json.dumps({
            "action": args.action, "mode": "offline_plan", "source_mutation": False,
            "network_commands_executed": False, "data_copied": False,
            "requirements": ["private libpq service/password files", "PostgreSQL client utilities",
                             "new private export directory", "empty staging target for restore",
                             "source write freeze for final DB + storage cutover",
                             "separate auth/storage/realtime/API replacement"],
        }, indent=2))
        return 0
    if not args.output:
        print("Migration refused: Set a private export directory outside Git.", file=sys.stderr)
        return 2
    actions = {"export-db": export_database, "export-storage": export_storage,
               "restore-db": restore_database, "verify-db": verify_database,
               "verify-storage": verify_storage}
    try:
        actions[args.action](args)
    except (MigrationError, OSError) as exc:
        print(f"Migration refused: {exc}", file=sys.stderr)
        return 2
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
