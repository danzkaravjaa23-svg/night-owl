import argparse
import contextlib
import copy
import importlib.util
import io
import json
from pathlib import Path
import tempfile
import unittest
from unittest import mock
from urllib import error

MODULE = Path(__file__).resolve().parents[1] / "export_public_media.py"
spec = importlib.util.spec_from_file_location("nightowl_public_media", MODULE)
media = importlib.util.module_from_spec(spec)
spec.loader.exec_module(media)


class PublicMediaSafetyTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.base = Path(self.temp.name).resolve()
        self.bytes = b"synthetic public image"
        self.buckets = [{"id": "posts", "name": "posts", "public": True},
                        {"id": "empty", "name": "empty", "public": True}]
        self.objects = [{"id": "object-one", "bucket_id": "posts", "name": "user/a picture.png",
                         "metadata": {"size": len(self.bytes), "mimetype": "image/png"}}]
        rows = [
            {"schema_name": "auth", "table_name": "users", "data": [{"private_test_secret": "do-not-log-auth-hash"}]},
            {"schema_name": "auth", "table_name": "identities", "data": []},
            {"schema_name": "public", "table_name": "profiles", "data": []},
            {"schema_name": "storage", "table_name": "objects", "data": self.objects},
            {"schema_name": "storage", "table_name": "buckets", "data": copy.deepcopy(self.buckets)},
        ]
        self.core = {"kind": "dashboard-read-only-core-snapshot", "completeDatabaseBackup": False,
                     "tables": rows}
        self.inventory = {"buckets": self.buckets}
        self.core_file, self.inventory_file = self.base / "core.json", self.base / "inventory.json"
        self.save_inputs()
        self.args = argparse.Namespace(core_snapshot=str(self.core_file), schema_inventory=str(self.inventory_file),
                                       source_origin="https://fixture.supabase.co", expected_table_count=5,
                                       expected_object_count=1, expected_bucket_count=2, output=str(self.base / "backup"))

    def tearDown(self):
        self.temp.cleanup()

    def save_inputs(self):
        self.core_file.write_text(json.dumps(self.core))
        self.core_file.chmod(0o600)
        self.inventory_file.write_text(json.dumps(self.inventory))
        self.inventory_file.chmod(0o600)

    def do_export(self):
        opener = mock.Mock()
        opener.open.return_value = io.BytesIO(self.bytes)
        with mock.patch.object(media.request, "build_opener", return_value=opener), \
                contextlib.redirect_stdout(io.StringIO()) as console:
            media.export(self.args)
        return opener, console.getvalue()

    def test_public_only_export_no_keys_or_auth_rows_and_full_byte_verify(self):
        opener, console = self.do_export()
        req = opener.open.call_args.args[0]
        self.assertIsNone(req.get_header("Authorization"))
        self.assertIsNone(req.get_header("Apikey"))
        self.assertIn("/storage/v1/object/public/posts/user/a%20picture.png", req.full_url)
        manifest_text = (Path(self.args.output) / "manifest.json").read_text()
        self.assertNotIn("do-not-log-auth-hash", manifest_text + console)
        manifest = json.loads(manifest_text)
        self.assertFalse(manifest["completeDatabaseBackup"])
        self.assertEqual(manifest["kind"], "supplemental-public-media-backup")
        self.assertEqual(manifest["object_count"], 1)
        self.assertEqual(len(manifest["buckets"]), 2)
        self.assertEqual(manifest["total_bytes"], len(self.bytes))
        media.verify(self.args)

    def test_default_plan_does_not_read_secret_files_or_open_network(self):
        command = ["export", "--core-snapshot", str(self.core_file), "--schema-inventory", str(self.inventory_file),
                   "--source-origin", self.args.source_origin, "--expected-table-count", "5",
                   "--expected-object-count", "1", "--expected-bucket-count", "2", "--output", self.args.output]
        with mock.patch.object(media.prepare_pgpass, "read_private", side_effect=AssertionError("file read")), \
                mock.patch.object(media.request, "build_opener", side_effect=AssertionError("network built")), \
                contextlib.redirect_stdout(io.StringIO()):
            self.assertEqual(media.main(command), 0)

    def test_private_unknown_or_non_boolean_public_bucket_refused_before_network(self):
        for flag in (False, None, "true"):
            self.inventory["buckets"][0]["public"] = flag
            self.save_inputs()
            with self.subTest(flag=flag), \
                    mock.patch.object(media.request, "build_opener", side_effect=AssertionError("network built")):
                with self.assertRaises(media.migrate.MigrationError):
                    media.export(self.args)
        self.assertFalse(Path(self.args.output).exists())

    def test_core_and_inventory_bucket_disagreement_refused(self):
        self.core["tables"][-1]["data"][0]["id"] = "other"
        self.save_inputs()
        with self.assertRaises(media.migrate.MigrationError):
            media.load_inputs(self.args)

    def test_incomplete_independent_table_or_object_counts_refused(self):
        for field in ("expected_table_count", "expected_object_count", "expected_bucket_count"):
            old = getattr(self.args, field)
            setattr(self.args, field, old + 1)
            with self.subTest(field=field), self.assertRaises(media.migrate.MigrationError):
                media.load_inputs(self.args)
            setattr(self.args, field, old)

    def test_duplicate_table_or_object_identities_refused(self):
        self.core["tables"].append(copy.deepcopy(self.core["tables"][0]))
        self.args.expected_table_count = 6
        self.save_inputs()
        with self.assertRaises(media.migrate.MigrationError):
            media.load_inputs(self.args)
        self.core["tables"].pop()
        self.args.expected_table_count = 5
        self.objects.append(copy.deepcopy(self.objects[0]))
        self.args.expected_object_count = 2
        self.save_inputs()
        with self.assertRaises(media.migrate.MigrationError):
            media.load_inputs(self.args)

    def test_private_object_unknown_bucket_or_missing_size_refused(self):
        self.objects[0]["bucket_id"] = "unknown"
        self.save_inputs()
        with self.assertRaises(media.migrate.MigrationError):
            media.load_inputs(self.args)
        self.objects[0]["bucket_id"] = "posts"
        del self.objects[0]["metadata"]["size"]
        self.save_inputs()
        with self.assertRaises(media.migrate.MigrationError):
            media.load_inputs(self.args)

    def test_delete_markers_and_versions_refused(self):
        for key in ("is_delete_marker", "is_versioned"):
            self.objects[0][key] = True
            self.save_inputs()
            with self.subTest(key=key), self.assertRaises(media.migrate.MigrationError):
                media.load_inputs(self.args)
            del self.objects[0][key]

    def test_path_traversal_refused_and_safe_names_use_hashed_local_path(self):
        self.objects[0]["name"] = "../a.png"
        self.save_inputs()
        with self.assertRaises(media.migrate.MigrationError):
            media.load_inputs(self.args)

    def test_changed_size_produces_no_success_manifest(self):
        self.objects[0]["metadata"]["size"] -= 1
        self.save_inputs()
        with self.assertRaises(media.migrate.MigrationError):
            self.do_export()
        self.assertFalse((Path(self.args.output) / "manifest.json").exists())

    def test_http_redirect_failure_is_not_followed_or_completed(self):
        opener = mock.Mock()
        opener.open.side_effect = error.HTTPError("https://fixture.supabase.co", 302, "redirect", {}, None)
        with mock.patch.object(media.request, "build_opener", return_value=opener):
            with self.assertRaises(media.migrate.MigrationError):
                media.export(self.args)
        self.assertFalse((Path(self.args.output) / "manifest.json").exists())

    def test_archive_corruption_or_changed_metadata_detected(self):
        self.do_export()
        file = next((Path(self.args.output) / "objects").iterdir())
        file.write_bytes(b"corrupt")
        with self.assertRaises(media.migrate.MigrationError):
            media.verify(self.args)

    def test_existing_output_and_user_symlink_refused(self):
        folder = Path(self.args.output)
        folder.mkdir(mode=0o700)
        with self.assertRaises(media.migrate.MigrationError):
            media.export(self.args)
        folder.rmdir()
        folder.symlink_to(self.base, target_is_directory=True)
        with self.assertRaises(media.migrate.MigrationError):
            media.export(self.args)

    def test_wrong_source_origin_fails_verification(self):
        self.do_export()
        self.args.source_origin = "https://other.example.invalid"
        with self.assertRaises(media.migrate.MigrationError):
            media.verify(self.args)


if __name__ == "__main__":
    unittest.main()
