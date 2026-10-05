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
        file = self.base / "database.dump"
        file.write_bytes(b"archive")
        migrate.write_json(self.base / "manifest.json", {
            "format_version": 1, "status": "database_export_complete",
            "source_service": "source", "server_version_num": 150000,
            "files": [{"path": file.name, "bytes": file.stat().st_size,
                       "sha256": migrate.file_hash(file)}],
            "tables": [],
        })
        return self.base

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
        migrate.write_json(storage / "manifest.json", {
            "format_version": 1, "status": "storage_export_complete",
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
        catalog = {"tables": [{"schema": schema, "table": table} for schema, table in required],
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
            return "archive TOC"
        with mock.patch.object(migrate, "binary", side_effect=lambda name: name), \
                mock.patch.object(migrate, "db_env", return_value={}), \
                mock.patch.object(migrate, "snapshot_session", side_effect=snapshot), \
                mock.patch.object(migrate, "query", side_effect=[catalog, {"buckets": [], "objects": []}]), \
                mock.patch.object(migrate, "command", side_effect=command), \
                mock.patch.object(migrate, "table_digest", side_effect=migrate.MigrationError("Unreadable auth table")):
            with self.assertRaises(migrate.MigrationError):
                migrate.export_database(args)
        self.assertTrue((output / "database.dump").exists())
        self.assertFalse((output / "manifest.json").exists())

    def test_private_storage_bytes_export_and_verify(self):
        self.bundle()
        data = b"synthetic private storage bytes"
        index = {"buckets": [{"id": "private", "public": False}, {"id": "empty", "public": True}],
                 "objects": [{"id": "fixture-object", "bucket_id": "private",
                              "name": "../private file.png", "metadata": {"size": len(data)}}]}
        (self.base / "storage-index.json").write_text(json.dumps(index))
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
