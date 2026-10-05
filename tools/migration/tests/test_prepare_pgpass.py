import contextlib
import importlib.util
import io
from pathlib import Path
import tempfile
import unittest
from unittest import mock

MODULE = Path(__file__).resolve().parents[1] / "prepare_pgpass.py"
spec = importlib.util.spec_from_file_location("nightowl_prepare_pgpass", MODULE)
helper = importlib.util.module_from_spec(spec)
spec.loader.exec_module(helper)


class CredentialPreparationTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.base = Path(self.temp.name).resolve()
        self.source_password = "source:password\\with trailing space "
        self.target_password = "target:password\\escaped"
        self.config = self.file("services.conf", """[nightowl_source]
host=source.example.invalid
port=5432
dbname=postgres
user=postgres.fixture
sslmode=require

[nightowl_staging]
host=127.0.0.1
port=55432
dbname=nightowl_staging
user=nightowl_owner
sslmode=disable
""")
        self.raw = self.file("source-password.txt", self.source_password + "\n")
        self.target = self.file("target-passfile", "127.0.0.1:55432:*:nightowl_owner:" +
                                helper.escape(self.target_password) + "\n")
        self.output = self.base / "new-pgpass"
        self.args = mock.Mock(service_file=str(self.config), source_service="nightowl_source",
                              target_service="nightowl_staging", source_password_file=str(self.raw),
                              target_passfile=str(self.target), output=str(self.output))

    def tearDown(self):
        self.temp.cleanup()

    def file(self, name, text):
        path = self.base / name
        path.write_text(text)
        path.chmod(0o600)
        return path

    def test_colon_backslash_escaped_and_both_credentials_round_trip(self):
        with contextlib.redirect_stdout(io.StringIO()) as output:
            helper.prepare(self.args)
        entries = helper.parse_passfile(self.output.read_text())
        self.assertEqual(entries[0], ["source.example.invalid", "5432", "postgres",
                                     "postgres.fixture", self.source_password])
        self.assertEqual(entries[1], ["127.0.0.1", "55432", "nightowl_staging",
                                     "nightowl_owner", self.target_password])
        self.assertIn("\\:", self.output.read_text())
        self.assertIn("\\\\", self.output.read_text())
        self.assertNotIn(self.source_password, output.getvalue())
        self.assertNotIn(self.target_password, output.getvalue())
        self.assertEqual(self.output.stat().st_mode & 0o777, 0o600)

    def test_dry_run_reads_no_file_and_connects_to_nothing(self):
        args = ["--source-password-file", str(self.raw), "--target-passfile", str(self.target),
                "--output", str(self.output)]
        with mock.patch.object(helper, "read_private", side_effect=AssertionError("secret read")), \
                contextlib.redirect_stdout(io.StringIO()):
            self.assertEqual(helper.main(args), 0)
        self.assertFalse(self.output.exists())

    def test_existing_output_is_never_overwritten(self):
        self.output.write_text("preserve original")
        self.output.chmod(0o600)
        with self.assertRaises(helper.migrate.MigrationError):
            helper.prepare(self.args)
        self.assertEqual(self.output.read_text(), "preserve original")

    def test_source_symlink_refused(self):
        linked = self.base / "linked-password"
        linked.symlink_to(self.raw)
        self.args.source_password_file = str(linked)
        with self.assertRaises(helper.migrate.MigrationError):
            helper.prepare(self.args)
        self.assertFalse(self.output.exists())

    def test_output_symlink_refused_and_target_preserved(self):
        self.output.symlink_to(self.raw)
        with self.assertRaises(helper.migrate.MigrationError):
            helper.prepare(self.args)
        self.assertEqual(self.raw.read_text(), self.source_password + "\n")

    def test_parent_symlink_refused(self):
        folder = self.base / "real"
        folder.mkdir(mode=0o700)
        linked = self.base / "linked"
        linked.symlink_to(folder, target_is_directory=True)
        self.args.output = str(linked / "pgpass")
        with self.assertRaises(helper.migrate.MigrationError):
            helper.prepare(self.args)
        self.assertFalse((folder / "pgpass").exists())

    def test_insecure_source_file_permissions_refused(self):
        self.raw.chmod(0o644)
        with self.assertRaises(helper.migrate.MigrationError):
            helper.prepare(self.args)

    def test_insecure_output_directory_refused(self):
        folder = self.base / "public"
        folder.mkdir(mode=0o755)
        self.args.output = str(folder / "pgpass")
        with self.assertRaises(helper.migrate.MigrationError):
            helper.prepare(self.args)

    def test_blank_password_does_not_create_passfile(self):
        self.raw.write_text("\n")
        with self.assertRaises(helper.migrate.MigrationError):
            helper.prepare(self.args)
        self.assertFalse(self.output.exists())

    def test_multiline_or_nul_password_refused(self):
        for value in ("one\ntwo\n", "one\x00two"):
            self.raw.write_text(value)
            with self.subTest(value=value), self.assertRaises(helper.migrate.MigrationError):
                helper.prepare(self.args)
        self.assertFalse(self.output.exists())

    def test_no_matching_target_entry_refused(self):
        self.target.write_text("other-host:55432:*:nightowl_owner:target\n")
        with self.assertRaises(helper.migrate.MigrationError):
            helper.prepare(self.args)

    def test_target_first_matching_entry_used_as_libpq_does(self):
        self.target.write_text("127.0.0.1:55432:*:nightowl_owner:first\n"
                               "127.0.0.1:55432:nightowl_staging:nightowl_owner:second\n")
        with contextlib.redirect_stdout(io.StringIO()):
            helper.prepare(self.args)
        self.assertEqual(helper.parse_passfile(self.output.read_text())[1][4], "first")

    def test_embedded_service_password_refused_without_leaking(self):
        self.config.write_text(self.config.read_text() + "password=private-inline-value\n")
        args = ["--execute", "--service-file", str(self.config),
                "--source-password-file", str(self.raw), "--target-passfile", str(self.target),
                "--output", str(self.output)]
        with contextlib.redirect_stderr(io.StringIO()) as output:
            self.assertEqual(helper.main(args), 2)
        self.assertNotIn("private-inline-value", output.getvalue())
        self.assertFalse(self.output.exists())

    def test_remote_service_must_require_tls(self):
        self.config.write_text(self.config.read_text().replace("sslmode=require", "sslmode=disable"))
        with self.assertRaises(helper.migrate.MigrationError):
            helper.prepare(self.args)

    def test_credentials_never_written_in_git_checkout(self):
        repo = self.base / "repo"
        (repo / ".git").mkdir(parents=True, mode=0o700)
        self.args.output = str(repo / "pgpass")
        with self.assertRaises(helper.migrate.MigrationError):
            helper.prepare(self.args)
        self.assertFalse((repo / "pgpass").exists())

    def test_crlf_editor_newline_preserves_password_whitespace(self):
        self.assertEqual(helper.password_line(" secret \r\n"), " secret ")
        self.assertEqual(helper.password_line(" secret "), " secret ")

    def test_invalid_passfile_escape_refused(self):
        for text in ("host:port:db:user:secret\\", "host:port:db:user:unescaped:colon"):
            with self.subTest(text=text), self.assertRaises(helper.migrate.MigrationError):
                helper.parse_passfile(text)


if __name__ == "__main__":
    unittest.main()
