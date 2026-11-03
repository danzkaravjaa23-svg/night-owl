import contextlib
import hashlib
import importlib.util
import io
import json
import os
from pathlib import Path
import tempfile
import unittest
from unittest import mock

MODULE = Path(__file__).resolve().parents[1] / "migrate.py"
spec = importlib.util.spec_from_file_location("nightowl_migrate", MODULE)
migrate = importlib.util.module_from_spec(spec)
spec.loader.exec_module(migrate)
fixture_spec = importlib.util.spec_from_file_location("nightowl_fixture", MODULE.parent / "tests" / "run_postgres_fixture.py")
fixture = importlib.util.module_from_spec(fixture_spec)
fixture_spec.loader.exec_module(fixture)


class MigrationSafetyTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.base = Path(self.temp.name).resolve()

    def tearDown(self):
        self.temp.cleanup()

    def bundle(self):
        coverage = migrate.rescue_table_coverage([], "")
        for name in migrate.DATABASE_ARTIFACTS:
            file = self.base / name
            if name == "table-data-coverage.json":
                migrate.write_json(file, coverage)
            elif name == "storage-index.json":
                migrate.write_json(file, {"buckets": [], "objects": []})
            else:
                file.write_bytes(b"; synthetic TOC\n" if name.endswith("toc.txt") else b"archive")
        migrate.write_json(self.base / "manifest.json", {
            "format_version": migrate.VERSION, "status": "database_export_complete",
            "source_service": "source", "server_version_num": 150000,
            "files": [{"path": name, "bytes": (self.base/name).stat().st_size,
                       "sha256": migrate.file_hash(self.base/name)} for name in sorted(migrate.DATABASE_ARTIFACTS)],
            "tables": [], "table_data_coverage": coverage,
        })
        return self.base

    def rehash_fixture_manifest(self):
        """Update intentionally changed synthetic input while constructing a fixture."""
        path = self.base / "manifest.json"
        manifest = json.loads(path.read_text())
        for item in manifest["files"]:
            file = self.base / item["path"]
            item.update(bytes=file.stat().st_size, sha256=migrate.file_hash(file))
        path.write_text(json.dumps(manifest))

    def storage_bundle(self):
        self.bundle()
        storage = self.base / "storage"
        (storage / "objects").mkdir(parents=True)
        data = b"private picture bytes"
        relative = migrate.object_file("private", "../a picture.png")
        file = storage / relative
        file.write_bytes(data)
        index = self.base / "storage-index.json"
        index.write_text(json.dumps({"objects": [{"bucket_id": "private", "name": "../a picture.png"}]}))
        self.rehash_fixture_manifest()
        migrate.write_json(storage / "manifest.json", {
            "format_version": migrate.VERSION, "status": "storage_export_complete",
            "index_sha256": migrate.file_hash(index),
            "objects": [{"bucket": "private", "name": "../a picture.png", "path": relative,
                         "bytes": len(data), "sha256": hashlib.sha256(data).hexdigest()}],
            "object_count": 1, "total_bytes": len(data),
        })
        return storage

    def test_default_plan_never_launches_database_or_network(self):
        with mock.patch.object(migrate.subprocess, "run", side_effect=AssertionError("command ran")), \
                mock.patch.object(migrate.subprocess, "Popen", side_effect=AssertionError("command ran")), \
                mock.patch.object(migrate.request, "build_opener", side_effect=AssertionError("network ran")), \
                contextlib.redirect_stdout(io.StringIO()) as output:
            for action in ("export-db", "export-storage", "restore-db", "verify-db", "verify-storage"):
                self.assertEqual(migrate.main([action]), 0)
        self.assertIn('"data_copied": false', output.getvalue())

    def test_url_not_accepted_as_service_alias(self):
        with self.assertRaises(migrate.MigrationError):
            migrate.service_name("postgres://user:secret@example/db")

    def test_private_key_file_mode_enforced(self):
        path = self.base / "key"
        path.write_text("key")
        path.chmod(0o644)
        with self.assertRaises(migrate.MigrationError):
            migrate.private_file(str(path), "key")
        path.chmod(0o600)
        self.assertEqual(migrate.private_file(str(path), "key"), path)

    def test_private_output_cannot_be_inside_checkout(self):
        repo = self.base / "repo"
        (repo / ".git").mkdir(parents=True)
        with self.assertRaises(migrate.MigrationError):
            migrate.outside_repository(repo / "ignored" / "backup")

    def test_manifest_detects_archive_corruption(self):
        self.bundle()
        (self.base / "database.dump").write_bytes(b"corrupt")
        with self.assertRaises(migrate.MigrationError):
            migrate.load_manifest(self.base)

    def test_manifest_requires_version_two_and_hashed_coverage_artifacts(self):
        self.bundle()
        path = self.base / "manifest.json"
        original = json.loads(path.read_text())
        variants = [{**original, "format_version": 1},
                    {**original, "files": original["files"] + [original["files"][0]]}]
        for name in migrate.DATABASE_ARTIFACTS:
            variants.append({**original, "files": [item for item in original["files"] if item["path"] != name]})
        for manifest in variants:
            path.write_text(json.dumps(manifest))
            with self.assertRaises(migrate.MigrationError):
                migrate.load_manifest(self.base)
        path.write_text(json.dumps(original))
        migrate.load_manifest(self.base)

    def test_manifest_recomputes_coverage_and_never_echoes_inventory_names(self):
        self.bundle()
        path = self.base / "manifest.json"
        original = json.loads(path.read_text())
        private_name = 'synthetic-private-table-name'
        manifest = {**original, "tables": [{"schema": private_name, "table": private_name,
                                           "oid": 777, "relation_kind": "r"}]}
        path.write_text(json.dumps(manifest))
        with self.assertRaises(migrate.MigrationError) as error:
            migrate.load_manifest(self.base)
        self.assertNotIn(private_name, str(error.exception))
        path.write_text(json.dumps(original))
        forged = {**original["table_data_coverage"], "table_data_relations": 20}
        (self.base / "table-data-coverage.json").write_text(json.dumps(forged))
        # Even correctly rehashed but inconsistent evidence must fail validation.
        self.rehash_fixture_manifest()
        with self.assertRaisesRegex(migrate.MigrationError, "does not match"):
            migrate.load_manifest(self.base)

    def test_old_manifest_cannot_reach_restore_target(self):
        self.bundle()
        path = self.base / "manifest.json"
        manifest = json.loads(path.read_text())
        manifest["format_version"] = 1
        path.write_text(json.dumps(manifest))
        args = mock.Mock(output=str(self.base), source="source", target="target", target_database="staging")
        with mock.patch.object(migrate, "validate_target", side_effect=AssertionError("target accessed")), \
                mock.patch.object(migrate, "command", side_effect=AssertionError("restore ran")):
            with self.assertRaisesRegex(migrate.MigrationError, "fresh export"):
                migrate.restore_database(args)

    def test_manifest_refuses_traversal_or_symlink(self):
        file = self.base / "safe"
        file.write_text("a")
        link = self.base / "link"
        link.symlink_to(file)
        for path in ("../safe", "/tmp/x", "link"):
            with self.subTest(path=path), self.assertRaises(migrate.MigrationError):
                migrate.artifact_path(self.base, path)

    def test_same_source_target_alias_refused_before_query(self):
        with mock.patch.object(migrate, "query", side_effect=AssertionError("query ran")):
            with self.assertRaises(migrate.MigrationError):
                migrate.validate_target("source", "source", "staging")

    def test_two_aliases_for_same_database_refused(self):
        identity = {"database": "db", "address": "10.0.0.1", "port": 5432}
        with mock.patch.object(migrate, "query", side_effect=[identity, identity]):
            with self.assertRaises(migrate.MigrationError):
                migrate.validate_target("source", "target", "db")

    def test_populated_target_refused_without_write(self):
        source = {"database": "source_db", "address": "source", "port": 5432}
        target = {"database": "staging", "address": "target", "port": 5432}
        with mock.patch.object(migrate, "query", side_effect=[source, target, {"tables": [{}]}]):
            with self.assertRaises(migrate.MigrationError):
                migrate.validate_target("source", "target", "staging")

    def test_wrong_declared_target_database_refused(self):
        source = {"database": "source_db", "address": "source", "port": 5432}
        target = {"database": "production", "address": "target", "port": 5432}
        with mock.patch.object(migrate, "query", side_effect=[source, target]):
            with self.assertRaises(migrate.MigrationError):
                migrate.validate_target("source", "target", "staging")

    def test_restore_is_transactional_target_only_never_clean(self):
        self.bundle()
        args = mock.Mock(output=str(self.base), source="source", target="target", target_database="staging")
        with mock.patch.object(migrate, "validate_target", return_value={"server_version_num": 150000}), \
                mock.patch.object(migrate, "db_env", return_value={}), \
                mock.patch.object(migrate, "binary", side_effect=lambda name: name), \
                mock.patch.object(migrate, "command") as command, \
                contextlib.redirect_stdout(io.StringIO()):
            migrate.restore_database(args)
        command_args = command.call_args.args[0]
        self.assertIn("--dbname=service=target", command_args)
        self.assertIn("--single-transaction", command_args)
        self.assertIn("--exit-on-error", command_args)
        for unsafe in ("--clean", "--create", "--disable-triggers"):
            self.assertNotIn(unsafe, command_args)
        self.assertNotIn("roles.sql", " ".join(command_args))

    def test_restore_refuses_older_major_version(self):
        self.bundle()
        args = mock.Mock(output=str(self.base), source="source", target="target", target_database="staging")
        with mock.patch.object(migrate, "validate_target", return_value={"server_version_num": 140000}), \
                mock.patch.object(migrate, "command", side_effect=AssertionError("write ran")):
            with self.assertRaises(migrate.MigrationError):
                migrate.restore_database(args)

    def test_verification_detects_missing_extra_and_modified_rows(self):
        def table(name, rows=1, checksum="a"):
            return {"schema": "public", "table": name, "rows": rows, "sha256_sorted_json": checksum}
        result = migrate.compare_tables([table("missing"), table("different")],
                                        [table("extra"), table("different", checksum="b")])
        self.assertEqual(result["missing"], [("public", "missing")])
        self.assertEqual(result["unexpected"], [("public", "extra")])
        self.assertEqual(result["different"], [("public", "different")])

    def test_storage_origins_refuse_plain_http_secret_or_redirect_query(self):
        for url in ("http://project.supabase.co", "https://user:secret@project.supabase.co",
                    "https://project.supabase.co/path", "https://project.supabase.co?key=secret"):
            with self.subTest(url=url), self.assertRaises(migrate.MigrationError):
                migrate.storage_base(url)

    def test_storage_object_names_cannot_escape_destination(self):
        path = migrate.object_file("bucket/../../", "../../../private.txt")
        self.assertRegex(path, r"^objects/[0-9a-f]{64}$")
        self.assertNotIn("..", path)

    def test_storage_rejects_redirects_to_other_hosts(self):
        self.assertIsNone(migrate.NoRedirect().redirect_request(None, None, 302, "", {}, "https://evil.test"))

    def test_storage_byte_checksum_verified(self):
        storage = self.storage_bundle()
        args = mock.Mock(output=str(self.base))
        with contextlib.redirect_stdout(io.StringIO()):
            migrate.verify_storage(args)
        next((storage / "objects").iterdir()).write_bytes(b"corrupt")
        with self.assertRaises(migrate.MigrationError):
            migrate.verify_storage(args)

    def test_storage_manifest_cannot_omit_an_object(self):
        storage = self.storage_bundle()
        manifest = json.loads((storage / "manifest.json").read_text())
        manifest["objects"] = []
        (storage / "manifest.json").write_text(json.dumps(manifest))
        with self.assertRaises(migrate.MigrationError):
            migrate.verify_storage(mock.Mock(output=str(self.base)))

    def test_read_only_transaction_imports_snapshot_and_quotes_identifiers(self):
        sql = migrate.transaction_sql("SELECT 1;", "00000001-00000002-1")
        self.assertIn("BEGIN ISOLATION LEVEL REPEATABLE READ READ ONLY;", sql)
        self.assertIn("SET TRANSACTION SNAPSHOT '00000001-00000002-1';", sql)
        self.assertEqual(migrate.identifier('strange"table'), '"strange""table"')

    def test_incomplete_source_export_never_creates_success_manifest(self):
        required = [("public", "profiles"), ("auth", "users"), ("auth", "identities"),
                    ("storage", "buckets"), ("storage", "objects")]
        catalog = {"tables": [{"schema": schema, "table": table, "oid": index + 100,
                               "relation_kind": "r"} for index, (schema, table) in enumerate(required)],
                   "server_version_num": 150000, "database": "source_db", "roles": [],
                   "extensions": [], "sequences": [], "foreign_tables": 0}
        output = self.base / "export"
        args = mock.Mock(source="source", output=str(output))
        @contextlib.contextmanager
        def snapshot(*args):
            yield "00000001-00000002-1"
        def command(args, *rest, **kwargs):
            for arg in args:
                if arg.startswith("--file="):
                    Path(arg.split("=", 1)[1]).write_bytes(b"archive")
            return "\n".join(f"{index + 1}; 0 {table['oid']} TABLE DATA {table['schema']} {table['table']} owner"
                             for index, table in enumerate(catalog["tables"]))
        with mock.patch.object(migrate, "binary", side_effect=lambda name: name), \
                mock.patch.object(migrate, "db_env", return_value={}), \
                mock.patch.object(migrate, "snapshot_session", side_effect=snapshot), \
                mock.patch.object(migrate, "query", side_effect=[catalog, {"buckets": [], "objects": []}]), \
                mock.patch.object(migrate, "command", side_effect=command), \
                mock.patch.object(migrate, "table_digest", side_effect=migrate.MigrationError("Unreadable auth table")):
            with self.assertRaisesRegex(migrate.MigrationError, "Unreadable auth table"):
                migrate.export_database(args)
        self.assertTrue((output / "database.dump").exists())
        self.assertFalse((output / "manifest.json").exists())

    def test_rescue_coverage_matches_oids_not_display_identifiers(self):
        tables = [{"schema": 'strange schema', "table": 'name "with quotes"',
                   "oid": 101, "relation_kind": "r"}]
        toc = "; archive comment\n3; 0 101 TABLE DATA strange schema name with quotes owner\n"
        self.assertEqual(migrate.rescue_table_coverage(tables, toc)["table_data_relations"], 1)
        for bad_toc in ("", toc.replace("0 101", "0 102"), toc + toc,
                        toc.replace("0 101", "1259 101"), "unrecognized TOC output"):
            with self.subTest(toc=bad_toc), self.assertRaises(migrate.MigrationError):
                migrate.rescue_table_coverage(tables, bad_toc)

    def test_rescue_coverage_requires_empty_tables_and_every_partition_leaf(self):
        tables = [{"schema": "public", "table": "parent", "oid": 101, "relation_kind": "p"},
                  {"schema": "public", "table": "leaf", "oid": 102, "relation_kind": "r"},
                  {"schema": "public", "table": "empty", "oid": 103, "relation_kind": "r"}]
        toc = "1; 0 102 TABLE DATA public leaf owner\n2; 0 103 TABLE DATA public empty owner\n"
        coverage = migrate.rescue_table_coverage(tables, toc)
        self.assertEqual(coverage["partitioned_parents"], 1)
        self.assertEqual(coverage["table_data_relations"], 2)
        self.assertEqual(migrate.rescue_table_coverage(tables[:1], "")["partitioned_parents"], 1)
        for invalid in (toc.splitlines()[0], toc + "3; 0 101 TABLE DATA public parent owner\n"):
            with self.subTest(toc=invalid), self.assertRaises(migrate.MigrationError):
                migrate.rescue_table_coverage(tables, invalid)

    def test_rescue_coverage_accounts_for_materialized_view_population(self):
        tables = [{"schema": "public", "table": "cached", "oid": 101,
                   "relation_kind": "m", "populated": True},
                  {"schema": "public", "table": "unpopulated", "oid": 102,
                   "relation_kind": "m", "populated": False}]
        toc = "1; 0 101 MATERIALIZED VIEW DATA public cached owner\n"
        coverage = migrate.rescue_table_coverage(tables, toc)
        self.assertEqual(coverage["materialized_view_refreshes"], 1)
        self.assertEqual(coverage["unpopulated_materialized_views"], 1)
        self.assertIs(coverage["materialized_view_rows_archived"], False)
        for invalid in ("", toc.replace("MATERIALIZED VIEW DATA", "TABLE DATA"),
                        toc + "2; 0 102 MATERIALIZED VIEW DATA public unpopulated owner\n"):
            with self.subTest(toc=invalid), self.assertRaises(migrate.MigrationError):
                migrate.rescue_table_coverage(tables, invalid)

    def test_unpopulated_materialized_view_digest_preserves_unreadable_state(self):
        table = {"schema": "public", "table": "unpopulated", "oid": 101,
                 "relation_kind": "m", "populated": False}
        with mock.patch.object(migrate.subprocess, "Popen", side_effect=AssertionError("SELECT ran")):
            digest = migrate.table_digest("source", table, "snapshot")
        self.assertEqual(digest["rows"], 0)
        self.assertEqual(digest["sha256_sorted_json"], hashlib.sha256(b"").hexdigest())
        # Equal empty row sets do not make populated and unpopulated states equal.
        changed = {**digest, "populated": True}
        self.assertEqual(migrate.compare_tables([digest], [changed])["different"], [("public", "unpopulated")])

    def test_extension_membership_and_configuration_filters_cannot_hide_omissions(self):
        table = {"schema": "extension_schema", "table": "settings", "oid": 101,
                 "relation_kind": "r", "extension_name": "example",
                 "extension_config": True, "extension_filter": ""}
        toc = "1; 0 101 TABLE DATA extension_schema settings owner\n"
        self.assertEqual(migrate.rescue_table_coverage([table], toc)["unfiltered_extension_config_tables"], 1)
        for condition in ("WHERE username = CURRENT_USER", "WHERE true", None):
            with self.subTest(condition=condition), self.assertRaisesRegex(migrate.MigrationError, "dump filter"):
                migrate.rescue_table_coverage([{**table, "extension_filter": condition}], toc)
        # A normal extension-owned table can be omitted even with explicit -t.
        with self.assertRaises(migrate.MigrationError):
            migrate.rescue_table_coverage([{**table, "extension_config": False, "extension_filter": None}], "")

    def test_rescue_coverage_rejects_missing_or_duplicate_catalog_identity(self):
        table = {"schema": "public", "table": "one", "oid": 101, "relation_kind": "r"}
        toc = "1; 0 101 TABLE DATA public one owner\n"
        for tables in ([{**table, "oid": None}], [{**table, "oid": True}],
                       [{**table, "relation_kind": "f"}], [table, table],
                       [{**table, "relation_kind": "m", "populated": None}]):
            with self.subTest(tables=tables), self.assertRaises(migrate.MigrationError):
                migrate.rescue_table_coverage(tables, toc)

    def test_export_manifest_waits_for_verified_rescue_toc_and_hashes_evidence(self):
        required = [("public", "profiles"), ("auth", "users"), ("auth", "identities"),
                    ("storage", "buckets"), ("storage", "objects")]
        tables = [{"schema": schema, "table": table, "oid": index + 100, "relation_kind": "r"}
                  for index, (schema, table) in enumerate(required)]
        catalog = {"tables": tables, "server_version_num": 170000, "database": "source_db", "roles": [],
                   "extensions": [], "sequences": [], "foreign_tables": 0}
        toc = "\n".join(f"{index + 1}; 0 {table['oid']} TABLE DATA {table['schema']} {table['table']} owner"
                        for index, table in enumerate(tables))
        @contextlib.contextmanager
        def snapshot(*args):
            yield "00000001-00000002-1"
        for omitted in (False, True):
            output = self.base / ("incomplete-coverage" if omitted else "complete-coverage")
            def command(args, *rest, **kwargs):
                for arg in args:
                    if arg.startswith("--file="):
                        Path(arg.split("=", 1)[1]).write_bytes(b"archive")
                if "--list" in args:
                    return toc.split("\n", 1)[1] if omitted and args[-1].endswith("all-table-data.dump") else toc
                return ""
            def digest(service, table, snapshot):
                return {**table, "rows": 0, "sha256_sorted_json": hashlib.sha256(b"").hexdigest()}
            with mock.patch.object(migrate, "binary", side_effect=lambda name: name), \
                    mock.patch.object(migrate, "db_env", return_value={}), \
                    mock.patch.object(migrate, "snapshot_session", side_effect=snapshot), \
                    mock.patch.object(migrate, "query", side_effect=[catalog, {"buckets": [], "objects": []}]), \
                    mock.patch.object(migrate, "command", side_effect=command), \
                    mock.patch.object(migrate, "table_digest", side_effect=digest) as table_digest, \
                    contextlib.redirect_stdout(io.StringIO()):
                args = mock.Mock(source="source", output=str(output))
                if omitted:
                    with self.assertRaisesRegex(migrate.MigrationError, "every expected relation"):
                        migrate.export_database(args)
                    table_digest.assert_not_called()
                    self.assertFalse((output / "manifest.json").exists())
                else:
                    migrate.export_database(args)
                    _, manifest = migrate.load_manifest(output)
                    self.assertEqual(manifest["table_data_coverage"]["table_data_relations"], 5)
                    self.assertTrue({"all-table-data-toc.txt", "table-data-coverage.json"}.issubset(
                        {file["path"] for file in manifest["files"]}))
                    (output / "table-data-coverage.json").write_text("corrupt")
                    with self.assertRaises(migrate.MigrationError):
                        migrate.load_manifest(output)

    def test_private_storage_bytes_export_and_verify(self):
        self.bundle()
        data = b"synthetic private storage bytes"
        index = {"buckets": [{"id": "private", "public": False}, {"id": "empty", "public": True}],
                 "objects": [{"id": "fixture-object", "bucket_id": "private",
                              "name": "../private file.png", "metadata": {"size": len(data)}}]}
        (self.base / "storage-index.json").write_text(json.dumps(index))
        self.rehash_fixture_manifest()
        key = self.base / "storage-key"
        key.write_text("fixture-service-key")
        key.chmod(0o600)
        opener = mock.Mock()
        opener.open.return_value = io.BytesIO(data)
        args = mock.Mock(output=str(self.base), storage_url="https://fixture.supabase.co",
                         storage_key_file=str(key))
        with mock.patch.object(migrate.request, "build_opener", return_value=opener), \
                contextlib.redirect_stdout(io.StringIO()):
            migrate.export_storage(args)
            migrate.verify_storage(args)
        req = opener.open.call_args.args[0]
        self.assertEqual(req.get_header("Authorization"), "Bearer fixture-service-key")
        self.assertIn("/storage/v1/object/private/", req.full_url)
        self.assertIn("private%20file.png", req.full_url)
        manifest = json.loads((self.base / "storage" / "manifest.json").read_text())
        self.assertEqual(manifest["object_count"], 1)
        self.assertEqual(manifest["total_bytes"], len(data))

    def test_changed_storage_size_cannot_get_success_manifest(self):
        self.bundle()
        index = {"buckets": [], "objects": [{"id": "fixture-object", "bucket_id": "private",
                                          "name": "a.png", "metadata": {"size": 100}}]}
        (self.base / "storage-index.json").write_text(json.dumps(index))
        self.rehash_fixture_manifest()
        key = self.base / "storage-key"
        key.write_text("fixture-service-key")
        key.chmod(0o600)
        opener = mock.Mock()
        opener.open.return_value = io.BytesIO(b"changed bytes")
        args = mock.Mock(output=str(self.base), storage_url="https://fixture.supabase.co",
                         storage_key_file=str(key))
        with mock.patch.object(migrate.request, "build_opener", return_value=opener):
            with self.assertRaises(migrate.MigrationError):
                migrate.export_storage(args)
        self.assertFalse((self.base / "storage" / "manifest.json").exists())

    def test_fixture_runner_plan_never_connects(self):
        with mock.patch.object(fixture.sys, "argv", ["fixture", "--admin-service", "anything"]), \
                mock.patch.object(fixture.migrate, "db_env", side_effect=AssertionError("connection configuration read")), \
                contextlib.redirect_stdout(io.StringIO()):
            self.assertEqual(fixture.main(), 0)

    def test_fixture_runner_refuses_remote_service_before_commands(self):
        services = self.base / "services.conf"
        services.write_text("[remote]\nhost=example.invalid\ndbname=production\n")
        with mock.patch.object(fixture.sys, "argv", ["fixture", "--admin-service", "remote", "--execute"]), \
                mock.patch.object(fixture.migrate, "db_env", return_value={"PGSERVICEFILE": str(services)}), \
                mock.patch.object(fixture.migrate, "command", side_effect=AssertionError("command ran")):
            with self.assertRaises(fixture.migrate.MigrationError):
                fixture.main()

    def test_permission_errors_write_private_diagnostics_without_console_rows(self):
        result = mock.Mock(returncode=1, stdout="", stderr="ERROR permission denied: private auth hash and row")
        log = self.base / "diagnostic.log"
        with mock.patch.object(migrate.subprocess, "run", return_value=result):
            with self.assertRaises(migrate.MigrationError) as error:
                migrate.command(["psql"], output=log)
        self.assertIn("Database access denied", str(error.exception))
        self.assertNotIn("private auth hash", str(error.exception))
        self.assertIn("private auth hash", log.read_text())
        self.assertEqual(log.stat().st_mode & 0o777, 0o600)

    def test_authentication_error_has_static_advice_without_password(self):
        result = mock.Mock(returncode=1, stdout="", stderr="password authentication failed for password SECRET")
        with mock.patch.object(migrate.subprocess, "run", return_value=result):
            with self.assertRaises(migrate.MigrationError) as error:
                migrate.command(["psql"])
        self.assertIn("private service/passfile", str(error.exception))
        self.assertNotIn("SECRET", str(error.exception))

    def test_diagnostics_never_overwrite_or_follow_existing_log_symlink(self):
        original = self.base / "original"
        original.write_text("preserve")
        link = self.base / "diagnostic.log"
        link.symlink_to(original)
        self.assertEqual(migrate.private_diagnostic("private secret", link), "")
        self.assertEqual(original.read_text(), "preserve")

    def test_error_does_not_print_database_error_or_secret(self):
        result = mock.Mock(returncode=1, stdout="", stderr="secret password and private row")
        with mock.patch.object(migrate.subprocess, "run", return_value=result):
            with self.assertRaises(migrate.MigrationError) as error:
                migrate.command(["psql"])
        self.assertNotIn("secret", str(error.exception))
        self.assertNotIn("private row", str(error.exception))


if __name__ == "__main__":
    unittest.main()
