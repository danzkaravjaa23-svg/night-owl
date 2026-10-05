import importlib.util
import json
from pathlib import Path
import tempfile
import unittest


SOURCE = Path(__file__).resolve().parents[1] / "preflight_secrets.py"
SPEC = importlib.util.spec_from_file_location("secret_preflight", SOURCE)
MODULE = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(MODULE)


class SecretPreflightTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.configuration = {"services": {
            "postgres": {"image": "postgres:test"},
            "postgrest": {"image": "postgrest:test"},
            "readiness": {"user": "65534:65534"},
        }, "secrets": {}}
        for name in dict.fromkeys(secret for names in MODULE.READERS.values() for secret in names):
            path = Path(self.temporary.name) / name
            path.write_text("fictional-fixture")
            path.chmod(0o600)
            self.configuration["secrets"][name] = {"file": str(path)}

    def runner(self, commands):
        if commands[:3] == ["docker", "image", "inspect"]:
            return json.dumps([{"Id": "sha256:" + "1" * 64, "Config": {"User": "1000:1000"}}])
        if commands[-1] == "id -u postgres; id -g postgres":
            return "999\n999"
        self.assertIn("none", commands)
        self.assertIn("--read-only", commands)
        self.assertIn("never", commands)
        self.assertNotIn("fictional-fixture", " ".join(commands))
        return ""

    def test_private_mounts_checked_as_each_runtime_uid_without_network_or_contents(self):
        results = MODULE.check(self.configuration, self.runner)
        self.assertEqual([entry["uid_gid"] for entry in results], ["999:999", "1000:1000", "65534:65534"])

    def test_world_readability_and_empty_files_fail_before_docker(self):
        path = Path(self.configuration["secrets"]["readiness_password"]["file"])
        path.chmod(0o644)
        with self.assertRaisesRegex(MODULE.PreflightError, "other users"):
            MODULE.check(self.configuration, lambda _: self.fail("Docker should not run"))
        path.chmod(0o600)
        path.write_text("")
        with self.assertRaisesRegex(MODULE.PreflightError, "nonempty private"):
            MODULE.private_files(self.configuration)

    def test_ambiguous_identity_fails_instead_of_assuming_image_gid(self):
        self.configuration["services"]["postgrest"]["user"] = "1000"
        with self.assertRaisesRegex(MODULE.PreflightError, "numeric UID:GID"):
            MODULE.check(self.configuration, self.runner)

    def test_unreadable_runtime_mount_has_secret_safe_named_blocker(self):
        def reject(commands):
            if "secret-check" in commands:
                raise MODULE.PreflightError("raw error containing fictional-fixture")
            return self.runner(commands)
        with self.assertRaises(MODULE.PreflightError) as caught:
            MODULE.check(self.configuration, reject)
        self.assertIn("postgres (999:999)", str(caught.exception))
        self.assertNotIn("fictional-fixture", str(caught.exception))


if __name__ == "__main__":
    unittest.main()
