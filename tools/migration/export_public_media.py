#!/usr/bin/env python3
"""Supplemental public-media rescue backup from a private dashboard snapshot.

No database connection, no API key and no authorization header. Every bucket
must be explicitly public in both snapshot and independent schema inventory.
This is not a complete database backup, storage destination upload or cutover.
"""
from __future__ import annotations

import argparse
import json
import os
from pathlib import Path
import sys
from urllib import error, parse, request

import migrate
import prepare_pgpass


def load_inputs(args):
    try:
        core = json.loads(prepare_pgpass.read_private(args.core_snapshot, "Core snapshot"))
        inventory = json.loads(prepare_pgpass.read_private(args.schema_inventory, "Schema inventory"))
    except (ValueError, UnicodeError):
        raise migrate.MigrationError("Private snapshot/inventory is not valid JSON.") from None
    if not isinstance(core, dict) or not isinstance(inventory, dict):
        raise migrate.MigrationError("Snapshot/inventory root must be an object.")
    if core.get("kind") != "dashboard-read-only-core-snapshot" or core.get("completeDatabaseBackup") is not False:
        raise migrate.MigrationError("Expected a supplemental dashboard snapshot explicitly marked as incomplete database backup.")
    tables = core.get("tables")
    if not isinstance(tables, list) or len(tables) != args.expected_table_count:
        raise migrate.MigrationError("Core snapshot table count does not match the independent expected count.")
    by_name = {}
    for table in tables:
        if not isinstance(table, dict) or not isinstance(table.get("data"), list):
            raise migrate.MigrationError("Snapshot contains malformed/incomplete table data.")
        identity = (table.get("schema_name"), table.get("table_name"))
        if not all(isinstance(part, str) and part for part in identity) or identity in by_name:
            raise migrate.MigrationError("Snapshot contains invalid or duplicate table identities.")
        by_name[identity] = table["data"]
    required = {("auth", "users"), ("auth", "identities"), ("public", "profiles"),
                ("storage", "objects"), ("storage", "buckets")}
    if not required.issubset(by_name):
        raise migrate.MigrationError("Snapshot is missing expected Auth/application/Storage tables.")
    schema_buckets = inventory.get("buckets")
    core_buckets = by_name[("storage", "buckets")]
    if not isinstance(schema_buckets, list):
        raise migrate.MigrationError("Schema inventory has no complete bucket metadata.")
    def buckets(items):
        mapping = {}
        for item in items:
            if not isinstance(item, dict) or not isinstance(item.get("id"), str) or not item["id"]:
                raise migrate.MigrationError("Invalid bucket identity.")
            if item["id"] in mapping:
                raise migrate.MigrationError("Duplicate bucket identity.")
            if item.get("public") is not True:
                raise migrate.MigrationError("Every bucket must be explicitly public; public rescue refuses private/unknown buckets.")
            mapping[item["id"]] = item
        if len(mapping) != args.expected_bucket_count:
            raise migrate.MigrationError("Bucket count does not match the independent expected count.")
        return mapping
    authoritative = buckets(schema_buckets)
    captured = buckets(core_buckets)
    if set(authoritative) != set(captured):
        raise migrate.MigrationError("Snapshot/inventory bucket identities do not match.")
    objects = by_name[("storage", "objects")]
    if len(objects) != args.expected_object_count:
        raise migrate.MigrationError("Object count does not match the independent expected count.")
    seen, seen_ids = set(), set()
    for item in objects:
        if not isinstance(item, dict):
            raise migrate.MigrationError("Invalid object metadata.")
        bucket, name, object_id = item.get("bucket_id"), item.get("name"), item.get("id")
        if (not isinstance(bucket, str) or bucket not in authoritative
                or not isinstance(name, str) or not name
                or not isinstance(object_id, str) or not object_id):
            raise migrate.MigrationError("Object metadata has an invalid bucket/name/id.")
        if any(part in (".", "..") for part in name.split("/")) or any(c in name for c in ("\0", "\r", "\n")):
            raise migrate.MigrationError("Object path contains unsafe segments/control characters.")
        if (bucket, name) in seen or object_id in seen_ids:
            raise migrate.MigrationError("Duplicate Storage object identity.")
        seen.add((bucket, name))
        seen_ids.add(object_id)
        if not isinstance(item.get("metadata"), dict):
            raise migrate.MigrationError("Object has no complete metadata.")
        size = item["metadata"].get("size")
        if not isinstance(size, int) or isinstance(size, bool) or size < 0:
            raise migrate.MigrationError("Every object needs a non-negative exact metadata byte size.")
        if item.get("is_delete_marker") is True or item.get("is_versioned") is True:
            raise migrate.MigrationError("Versioned/deletion-marker objects require a separate complete Storage version export.")
    return objects, authoritative


def export(args):
    origin = migrate.storage_base(args.source_origin)
    output = prepare_pgpass.no_symlinks(args.output)
    if output.exists():
        raise migrate.MigrationError("Output must be a new private directory; existing exports are never overwritten.")
    if not output.parent.is_dir() or output.parent.stat().st_mode & 0o077:
        raise migrate.MigrationError("Output parent must be an existing private directory with permissions 700.")
    objects, buckets = load_inputs(args)
    output.mkdir(mode=0o700)
    (output / "objects").mkdir(mode=0o700)
    opener = request.build_opener(migrate.NoRedirect())
    copied = []
    for item in objects:
        bucket, name = item["bucket_id"], item["name"]
        expected = item["metadata"]["size"]
        relative = migrate.object_file(bucket, name)
        url = origin + "/storage/v1/object/public/" + parse.quote(bucket, safe="") + "/" + parse.quote(name, safe="/")
        # Explicitly unauthenticated. No private file content becomes an HTTP header.
        req = request.Request(url, headers={"Accept-Encoding": "identity"})
        size = 0
        try:
            with opener.open(req, timeout=60) as response, (output / relative).open("xb") as handle:
                os.chmod(output / relative, 0o600)
                for chunk in iter(lambda: response.read(1024 * 1024), b""):
                    size += len(chunk)
                    if size > expected:
                        raise migrate.MigrationError("Public object exceeds snapshot byte size; export incomplete.")
                    handle.write(chunk)
        except error.HTTPError as http_error:
            http_error.close()
            raise migrate.MigrationError("Unauthenticated public object download failed; export incomplete.") from None
        except (error.URLError, OSError):
            raise migrate.MigrationError("Unauthenticated public object download failed; export incomplete.") from None
        if size != expected:
            raise migrate.MigrationError("Public object byte size changed since snapshot; export incomplete.")
        copied.append({"bucket": bucket, "name": name, "object_id": item["id"], "path": relative,
                       "bytes": size, "sha256": migrate.file_hash(output / relative),
                       "metadata": item["metadata"]})
    migrate.write_json(output / "manifest.json", {
        "format_version": 1, "kind": "supplemental-public-media-backup",
        "completeDatabaseBackup": False, "status": "public_media_export_complete",
        "created_at": migrate.now(), "core_snapshot_sha256": migrate.file_hash(Path(args.core_snapshot)),
        "schema_inventory_sha256": migrate.file_hash(Path(args.schema_inventory)),
        "source_origin": origin, "buckets": list(buckets.values()), "objects": copied,
        "object_count": len(copied), "total_bytes": sum(item["bytes"] for item in copied),
        "authorization_headers_used": False, "destination_upload_verified": False,
        "consistency": "Dashboard metadata and media bytes are separate reads; source writes must be frozen for final cutover.",
    })
    verify(args)
    print(f"Supplemental public-media backup complete: {len(copied)} objects. Not a full database migration.")


def verify(args):
    folder = prepare_pgpass.no_symlinks(args.output)
    try:
        manifest = json.loads(prepare_pgpass.read_private(folder / "manifest.json", "Public-media manifest"))
        if (manifest.get("kind") != "supplemental-public-media-backup"
                or manifest.get("completeDatabaseBackup") is not False
                or manifest.get("status") != "public_media_export_complete"):
            raise migrate.MigrationError("Unsupported/incomplete supplemental public-media manifest.")
        objects, buckets = load_inputs(args)
        if manifest.get("source_origin") != migrate.storage_base(args.source_origin):
            raise migrate.MigrationError("Backup source origin differs from declared source.")
        if (manifest["core_snapshot_sha256"] != migrate.file_hash(Path(args.core_snapshot))
                or manifest["schema_inventory_sha256"] != migrate.file_hash(Path(args.schema_inventory))):
            raise migrate.MigrationError("Input metadata checksum mismatch.")
        expected = {(item["bucket_id"], item["name"], item["id"]) for item in objects}
        copied = {(item["bucket"], item["name"], item["object_id"]) for item in manifest["objects"]}
        if copied != expected or len(manifest["objects"]) != len(expected):
            raise migrate.MigrationError("Backup Storage identity/count mismatch.")
        for item in manifest["objects"]:
            file = migrate.artifact_path(folder, item["path"])
            if file.stat().st_size != item["bytes"] or migrate.file_hash(file) != item["sha256"]:
                raise migrate.MigrationError("Public-media binary checksum/size mismatch.")
        if manifest["object_count"] != len(expected) or manifest["total_bytes"] != sum(item["bytes"] for item in manifest["objects"]):
            raise migrate.MigrationError("Public-media manifest totals mismatch.")
        if {item["id"] for item in manifest["buckets"]} != set(buckets):
            raise migrate.MigrationError("Backup bucket identity mismatch.")
    except (ValueError, KeyError, OSError, TypeError):
        raise migrate.MigrationError("Cannot verify supplemental public-media archive.") from None


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("action", choices=("export", "verify"))
    parser.add_argument("--execute", action="store_true")
    parser.add_argument("--core-snapshot", required=True)
    parser.add_argument("--schema-inventory", required=True)
    parser.add_argument("--source-origin", required=True)
    parser.add_argument("--expected-table-count", type=int, required=True)
    parser.add_argument("--expected-object-count", type=int, required=True)
    parser.add_argument("--expected-bucket-count", type=int, required=True)
    parser.add_argument("--output", required=True)
    args = parser.parse_args(argv)
    if not args.execute:
        print("Offline supplemental public-media plan only. No data read/copied and no keys/network used.")
        return 0
    try:
        if min(args.expected_table_count, args.expected_object_count, args.expected_bucket_count) < 1:
            raise migrate.MigrationError("Independent expected counts must be positive.")
        {"export": export, "verify": verify}[args.action](args)
    except (migrate.MigrationError, OSError, UnicodeError, ValueError, TypeError, KeyError, AttributeError) as error:
        message = str(error) if isinstance(error, migrate.MigrationError) else "Supplemental public-media operation could not complete."
        print(f"Public-media operation refused: {message}", file=sys.stderr)
        return 2
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
