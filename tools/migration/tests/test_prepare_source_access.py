import contextlib
import importlib.util
import io
import os
from pathlib import Path
import sys
import tempfile
import unittest
from unittest import mock
import warnings

TOOL_DIR = Path(__file__).resolve().parents[1]
if str(TOOL_DIR) not in sys.path:
    sys.path.insert(0, str(TOOL_DIR))
spec = importlib.util.spec_from_file_location("nightowl_prepare_source_access", TOOL_DIR / "prepare_source_access.py")
helper = importlib.util.module_from_spec(spec)
spec.loader.exec_module(helper)


class Terminal(io.StringIO):
    def __init__(self, tty=True):
        super().__init__()
        self.tty = tty

    def isatty(self):
        return self.tty


class SourceAccessTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.base = Path(self.temp.name).resolve()
        self.output = self.base / "source-access"
        self.password = " private:password\\with spaces "
        self.values = dict(host="source.example.invalid", port=5432, database="postgres",
                           user="postgres.fixture", service="nightowl_source",
                           sslrootcert="system", output=str(self.output))

    def tearDown(self):
        self.temp.cleanup()

    def argv(self, execute=True, **changes):
        values = {**self.values, **changes}
        return (["--execute"] if execute else []) + [part for key, value in values.items() for part in ("--" + key, str(value))]

    def run_helper(self, *, stdin_tty=True, stderr_tty=True, prompt=None, execute=True, **changes):
        output, error = io.StringIO(), Terminal(stderr_tty)
        with mock.patch.object(helper.sys, "stdin", Terminal(stdin_tty)), \
                contextlib.redirect_stdout(output), contextlib.redirect_stderr(error), \
                mock.patch.object(helper.getpass, "getpass", **({"side_effect": prompt} if prompt else {"return_value": self.password})) as read:
            result = helper.main(self.argv(execute, **changes))
        return result, output.getvalue() + error.getvalue(), read

    def test_default_plan_has_no_prompt_or_filesystem_access(self):
        with mock.patch.object(helper, "prepare", side_effect=AssertionError("plan executed")):
            result, log, read = self.run_helper(execute=False, output="/does/not/exist/new")
        self.assertEqual(result, 0)
        read.assert_not_called()
        self.assertFalse(self.output.exists())
        self.assertIn("Offline plan", log)

    def test_private_source_only_files_round_trip_password_and_enforce_tls(self):
        result, log, read = self.run_helper()
        self.assertEqual(result, 0)
        read.assert_called_once()
        self.assertNotIn(self.password, log)
        self.assertEqual(set(p.name for p in self.output.iterdir()), {"service.conf", "pgpass"})
        self.assertEqual(self.output.stat().st_mode & 0o777, 0o700)
        for child in self.output.iterdir():
            self.assertEqual(child.stat().st_mode & 0o777, 0o600)
        self.assertEqual(helper.prepare_pgpass.parse_passfile((self.output / "pgpass").read_text()),
                         [["source.example.invalid", "5432", "postgres", "postgres.fixture", self.password]])
        service = (self.output / "service.conf").read_text()
        self.assertIn("sslmode=verify-full\nsslrootcert=system\n", service)
        self.assertNotIn(self.password, service)
        self.assertNotIn("staging", service)

    def test_ipv6_colons_are_escaped_for_libpq(self):
        result, _, _ = self.run_helper(host="2001:db8::17")
        self.assertEqual(result, 0)
        entry = helper.prepare_pgpass.parse_passfile((self.output / "pgpass").read_text())[0]
        self.assertEqual(entry[0], "2001:db8::17")
        self.assertEqual(entry[4], self.password)

    def test_explicit_existing_ca_path_is_saved_without_reading_contents(self):
        ca = self.base / "root CA.crt"
        ca.write_text("public fixture, not a real CA")
        with mock.patch.object(Path, "read_text", side_effect=AssertionError("file contents read")):
            result, _, _ = self.run_helper(sslrootcert=str(ca))
        self.assertEqual(result, 0)
        self.assertIn("sslrootcert=" + str(ca), (self.output / "service.conf").read_text())

    def test_redirected_input_or_error_output_refuses_before_prompt(self):
        for stdin, stderr in [(False, True), (True, False), (False, False)]:
            with self.subTest(stdin=stdin, stderr=stderr):
                result, _, read = self.run_helper(stdin_tty=stdin, stderr_tty=stderr)
                self.assertEqual(result, 2)
                read.assert_not_called()
                self.assertFalse(self.output.exists())

    def test_getpass_echo_fallback_is_aborted_before_returning_input(self):
        continued = []
        def fallback(*args, **kwargs):
            warnings.warn("Cannot hide input", helper.getpass.GetPassWarning)
            continued.append(True)
            return self.password
        result, log, _ = self.run_helper(prompt=fallback)
        self.assertEqual(result, 2)
        self.assertFalse(continued)
        self.assertNotIn(self.password, log)
        self.assertFalse(self.output.exists())

    def test_empty_multiline_nul_and_cancelled_input_never_saved(self):
        for value in ["", "one\ntwo", "one\rtwo", "one\0two"]:
            with self.subTest(value=repr(value)):
                result, log, _ = self.run_helper(prompt=lambda *a, **k: value)
                self.assertEqual(result, 2)
                self.assertFalse(self.output.exists())
                if value:
                    self.assertNotIn(value, log)
        for error in [EOFError(self.password), KeyboardInterrupt(), RuntimeError(self.password)]:
            result, log, _ = self.run_helper(prompt=error)
            self.assertEqual(result, 2)
            self.assertNotIn(self.password, log)
            self.assertFalse(self.output.exists())

    def test_existing_directory_and_existing_file_are_never_overwritten(self):
        self.output.mkdir()
        original = self.output / "pgpass"
        original.write_text("preserve existing credential")
        result, _, read = self.run_helper()
        self.assertEqual(result, 2)
        read.assert_not_called()
        self.assertEqual(original.read_text(), "preserve existing credential")
        original.unlink(); self.output.rmdir()
        self.output.write_text("preserve existing file")
        result, _, read = self.run_helper()
        self.assertEqual(result, 2)
        read.assert_not_called()
        self.assertEqual(self.output.read_text(), "preserve existing file")

    def test_symlinked_output_parent_and_ca_are_refused(self):
        real = self.base / "real"
        real.mkdir(mode=0o700)
        linked = self.base / "linked"
        linked.symlink_to(real, target_is_directory=True)
        ca = self.base / "certificate"
        ca.write_text("public CA fixture")
        ca_link = self.base / "linked-ca"
        ca_link.symlink_to(ca)
        self.output.symlink_to(real, target_is_directory=True)
        for changes in [{}, {"output": str(linked / "new")}, {"sslrootcert": str(ca_link), "output": str(self.base / "other")}]:
            result, _, read = self.run_helper(**changes)
            self.assertEqual(result, 2)
            read.assert_not_called()
        self.assertEqual(list(real.iterdir()), [])

    def test_git_checkout_parent_traversal_and_shared_parent_refused(self):
        checkout = self.base / "checkout"
        checkout.mkdir(mode=0o700)
        (checkout / ".git").write_text("gitdir: fixture")
        shared = self.base / "shared"
        shared.mkdir(mode=0o777); shared.chmod(0o777)
        for path in [checkout / "new", self.base / "nested" / ".." / "new", shared / "new", Path("relative-output")]:
            result, _, read = self.run_helper(output=str(path))
            self.assertEqual(result, 2)
            read.assert_not_called()

    def test_invalid_connection_fields_and_ca_refused_without_prompt(self):
        for changes in [{"host": "https://source.test"}, {"host": "a,b"}, {"host": "*"},
                        {"host": "ok\nsslmode=disable"}, {"host": "fe80::1%bad"}, {"port": 0}, {"port": 65536},
                        {"database": "*"}, {"user": "ok\npassword=x"}, {"service": "bad]"},
                        {"sslrootcert": "relative.crt"}, {"sslrootcert": str(self.base / "missing.crt")}]:
            with self.subTest(changes=changes):
                result, _, read = self.run_helper(**changes)
                self.assertEqual(result, 2)
                read.assert_not_called()
                self.assertFalse(self.output.exists())

    def test_partial_write_failure_cleans_only_new_attempt_and_hides_error(self):
        real_write = helper.write_private
        def fail_second(fd, name, text, created):
            real_write(fd, name, text, created)
            if name == "pgpass":
                raise OSError(self.password)
        with mock.patch.object(helper, "write_private", side_effect=fail_second):
            result, log, _ = self.run_helper()
        self.assertEqual(result, 2)
        self.assertNotIn(self.password, log)
        self.assertFalse(self.output.exists())

    def test_mkdir_race_never_opens_or_overwrites_an_existing_directory(self):
        real_mkdir = helper.os.mkdir
        def race(name, *args, **kwargs):
            real_mkdir(name, *args, **kwargs)
            (self.output / "keep").write_text("another attempt")
            raise FileExistsError(self.password)
        with mock.patch.object(helper.os, "mkdir", side_effect=race):
            result, log, _ = self.run_helper()
        self.assertEqual(result, 2)
        self.assertNotIn(self.password, log)
        self.assertEqual((self.output / "keep").read_text(), "another attempt")


if __name__ == "__main__":
    unittest.main()
