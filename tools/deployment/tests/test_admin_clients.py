import base64
import importlib.util
import json
from pathlib import Path
import sys
import tempfile
import unittest


SCRIPT = Path(__file__).resolve().parents[1] / "build_admin_clients.py"
spec = importlib.util.spec_from_file_location("admin_clients", SCRIPT)
module = importlib.util.module_from_spec(spec)
sys.modules[spec.name] = module
spec.loader.exec_module(module)


def token(claims, alg="HS256"):
    def segment(value):
        return base64.urlsafe_b64encode(json.dumps(value).encode()).decode().rstrip("=")
    return ".".join((segment({"alg": alg}), segment(claims), base64.urlsafe_b64encode(b"fixture-signature").decode().rstrip("=")))


class AdminClientTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name) / "source"
        self.url = "https://legacy.supabase.co"
        self.key = token({"role": "anon", "exp": 4102444800})
        self.new_key = token({"role": "anon", "aud": "authenticated", "exp": 4102444800})
        self.values = {"BACKEND_MODE": "postgres", "BACKEND_URL": "https://api.nightowl.test:8443", "BACKEND_PUBLIC_KEY": self.new_key}
        for relative in module.RUNTIME_FILES:
            target = self.root / relative
            target.parent.mkdir(parents=True, exist_ok=True)
            source = f"const SUPABASE_URL = '{self.url}';\nconst SUPABASE_ANON = '{self.key}';\n"
            source += "const sb = supabase.createClient(SUPABASE_URL, SUPABASE_ANON);" if relative.startswith("web/") else "const SESSION_KEY = 'no_admin_session';"
            target.write_text(source)
        manifest = {"manifest_version": 3, "host_permissions": [self.url + "/*"], "permissions": ["storage", "alarms", "badges"], "content_security_policy": {"extension_pages": "script-src 'self'; object-src 'self'"}}
        (self.root / "chrome-extension/manifest.json").write_text(json.dumps(manifest))
        for relative in ("chrome-extension/popup/popup.html", "chrome-extension/dashboard/dashboard.html"):
            target = self.root / relative
            target.parent.mkdir(parents=True, exist_ok=True)
            target.write_text("Supabase холбоотой — Supabase-р нэвтрэх")
        self.output = Path(self.temp.name) / "generated"

    def config(self, values=None):
        return module.ClientConfig.parse(values or self.values, module.source_defaults(self.root))

    def test_default_preserves_current_backend(self):
        config = module.ClientConfig.parse({}, module.source_defaults(self.root))
        self.assertEqual((config.mode, config.url, config.public_key), ("supabase", self.url, self.key))

    def test_clean_checkout_legacy_admin_directory_builds_without_staged_rename(self):
        (self.root / "web/admin").rename(self.root / "admin-web")
        config = self.config()
        receipt = module.build(self.root, self.output, config)
        output = (self.output / "web-admin/index.html").read_text()
        self.assertEqual(module.constant(output, "SUPABASE_URL"), config.url)
        self.assertIn(config.session_key, output)
        self.assertIn("admin-web/index.html", receipt["source_sha256"])
        self.assertTrue((self.root / "admin-web/index.html").is_file())
        self.assertFalse((self.root / "web/admin").exists())

    def test_independent_requires_endpoint_and_public_credential_together(self):
        for values in ({"BACKEND_MODE": "postgres"}, {"BACKEND_MODE": "postgres", "BACKEND_URL": "https://api.nightowl.test"}, {"BACKEND_MODE": "postgres", "BACKEND_PUBLIC_KEY": self.new_key}):
            with self.assertRaises(module.BuildError):
                self.config(values)
        self.assertFalse(self.output.exists())

    def test_server_and_personal_tokens_are_refused(self):
        for key in ("sb_secret_do_not_publish", token({"role": "service_role"}), token({"role": "authenticated"}), token({"role": "anon", "aud": "authenticated", "sub": "user-id"}), token({"role": "anon", "aud": "authenticated", "sub": 0}), token({"role": "anon", "aud": "authenticated"}, alg="none")):
            with self.subTest(key_type=key[:10]), self.assertRaises(module.BuildError):
                self.config({**self.values, "BACKEND_PUBLIC_KEY": key})

    def test_independent_requires_matching_audience_and_unexpired_token(self):
        for claims in ({"role": "anon"}, {"role": "anon", "aud": "other"}, {"role": "anon", "aud": "authenticated", "exp": 1}):
            with self.assertRaises(module.BuildError):
                self.config({**self.values, "BACKEND_PUBLIC_KEY": token(claims)})

    def test_origin_validation_and_explicit_loopback_exception(self):
        for url in (self.url, "https://other.supabase.in", "http://api.nightowl.test", "postgresql://db.test/nightowl", "https://user:secret@api.test", "https://api.test/rest/v1", "https://api.test?secret=value", "https://api.test:0"):
            with self.subTest(url=url), self.assertRaises(module.BuildError):
                self.config({**self.values, "BACKEND_URL": url})
        config = module.ClientConfig.parse({**self.values, "BACKEND_URL": "http://127.0.0.1:8787"}, module.source_defaults(self.root), allow_local_http=True)
        self.assertEqual(config.url, "http://127.0.0.1:8787")

    def test_server_config_fields_are_never_accepted(self):
        with self.assertRaises(module.BuildError):
            self.config({**self.values, "DATABASE_URL": "private-server-secret"})

    def test_generated_bundle_covers_runtime_manifest_and_sessions_without_source_edits(self):
        before = {str(path): path.read_bytes() for path in self.root.rglob("*") if path.is_file()}
        config = self.config()
        module.build(self.root, self.output, config)
        runtime = [self.output / "web-admin/index.html", self.output / "chrome-extension/lib/supabase-client.js", self.output / "chrome-extension/background/service_worker.js"]
        for path in runtime:
            text = path.read_text()
            self.assertEqual(module.constant(text, "SUPABASE_URL"), config.url)
            self.assertEqual(module.constant(text, "SUPABASE_ANON"), config.public_key)
            self.assertIn(config.session_key, text)
            self.assertNotIn(self.url, text)
        manifest = json.loads((self.output / "chrome-extension/manifest.json").read_text())
        self.assertEqual(manifest["host_permissions"], [config.url + "/*"])
        self.assertIn(config.url, manifest["content_security_policy"]["extension_pages"])
        self.assertNotIn("badges", manifest["permissions"])
        after = {str(path): path.read_bytes() for path in self.root.rglob("*") if path.is_file()}
        self.assertEqual(before, after)

    def test_sources_with_mixed_backends_stop_generation(self):
        target = self.root / module.RUNTIME_FILES[-1]
        target.write_text(target.read_text().replace(self.url, "https://another.supabase.co"))
        with self.assertRaises(module.BuildError):
            module.source_defaults(self.root)

    def test_only_own_generated_bundle_can_be_replaced(self):
        self.output.mkdir()
        unrelated = self.output / "unrelated.txt"
        unrelated.write_text("preserve")
        with self.assertRaises(module.BuildError):
            module.build(self.root, self.output, self.config())
        self.assertEqual(unrelated.read_text(), "preserve")
        fresh = Path(self.temp.name) / "fresh"
        module.build(self.root, fresh, self.config())
        other = self.config({**self.values, "BACKEND_URL": "https://next.nightowl.test"})
        module.build(self.root, fresh, other)
        self.assertEqual(module.constant((fresh / "web-admin/index.html").read_text(), "SUPABASE_URL"), other.url)

    def test_flutter_defines_are_exactly_public_settings(self):
        config = self.config()
        target = Path(self.temp.name) / "backend-defines.json"
        module.write_defines(self.root, target, config)
        defines = json.loads(target.read_text())
        self.assertEqual(set(defines), module.CONFIG_KEYS)
        self.assertEqual(defines, config.public_defines())
        self.assertNotEqual(config.session_key, module.ClientConfig("supabase", config.url, config.public_key).session_key)


if __name__ == "__main__":
    unittest.main()
