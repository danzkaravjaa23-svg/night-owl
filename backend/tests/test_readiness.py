"""Offline tests for the release gate, not proof of a restored live database."""

import importlib.util
import json
from pathlib import Path
import subprocess
import tempfile
import unittest
from unittest.mock import patch


BACKEND = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location("readiness", BACKEND / "gateway/readiness.py")
readiness = importlib.util.module_from_spec(spec)
spec.loader.exec_module(readiness)


class ReadinessTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.key = Path(self.temp.name) / "verification-key"
        self.key.write_text("a" * 64)  # Presence fixture; never a production JWT key.
        self.env = {
            "APP_WEB_ORIGIN": "https://nightowl-ub.netlify.app",
            "AUTH_UPSTREAM": "http://auth:9999",
            "STORAGE_UPSTREAM": "http://storage:5000",
            "REALTIME_UPSTREAM": "http://realtime:4000",
            "AUTH_READY_PATH": "/auth/v1/health",
            "STORAGE_READY_PATH": "/storage/v1/status",
            "REALTIME_READY_PATH": "/realtime/v1/health",
            "UPSTREAM_PROTOCOL_VERIFIED": "true",
            "CUTOVER_APPROVED": "true",
            "JWT_VERIFICATION_KEY_FILE": str(self.key),
            "POSTGREST_READY_URL": "http://postgrest:3001/ready",
        }

    def test_unconfigured_gate_never_queries_or_proxies(self):
        def forbidden(*_args):
            self.fail("Unconfigured gate performed an upstream/database request")
        report = readiness.evaluate_readiness({}, probe=forbidden, inventory=forbidden)
        self.assertFalse(report["ready"])
        self.assertIn("auth_upstream_unconfigured", report["issues"])
        self.assertIn("cutover_approved_required", report["issues"])

    def test_unhealthy_database_fails_before_service_probes(self):
        def forbidden(*_args):
            self.fail("Incomplete database should not probe services")
        report = readiness.evaluate_readiness(
            self.env, probe=forbidden, inventory=lambda _: {"ready": False})
        self.assertEqual(report, {"ready": False, "issues": ["database_inventory_incomplete"]})

    def test_healthy_metadata_and_all_services_required(self):
        seen = []
        def probe(url):
            seen.append(url)
            return not url.startswith("http://realtime:")
        report = readiness.evaluate_readiness(
            self.env, probe=probe, inventory=lambda _: {"ready": True})
        self.assertEqual(report, {"ready": False, "issues": ["realtime_unavailable"]})
        self.assertEqual(len(seen), 4)
        report = readiness.evaluate_readiness(
            self.env, probe=lambda _: True, inventory=lambda _: {"ready": True})
        self.assertTrue(report["ready"])

    def test_supabase_credentials_in_url_and_public_plain_http_are_refused(self):
        for origin in (
            "https://project.supabase.co", "https://user:password@api.test",
            "https://api.test/path", "https://api.test?token=secret",
            "http://remote.provider.test", "https://127.0.0.1:8787",
            "https://unconfigured.invalid", "http://[", "http://auth:0",
        ):
            with self.subTest(origin=origin):
                self.assertFalse(readiness.valid_origin(origin))

    def test_health_paths_cannot_change_origin_or_embed_secrets(self):
        for path in ("https://other.test/health", "//other.test/health", "/health?token=secret", "/health#ok", "//[", ""):
            with self.subTest(path=path):
                self.assertFalse(readiness.valid_health_path(path))

    def test_missing_and_placeholder_verification_keys_fail_closed(self):
        for contents in ("", "short", "replace_me" * 20, "{not-json}"):
            self.key.write_text(contents)
            self.assertFalse(readiness.verification_key_configured(str(self.key)))
        self.assertFalse(readiness.verification_key_configured("/no-such-key"))

    def test_all_public_gate_health_routes_fail_closed(self):
        cache = readiness.ReadinessCache({}, evaluate=lambda _: {"ready": False, "issues": ["auth_unavailable"]})
        for path in ("/healthz", "/readyz", "/gate"):
            self.assertEqual(readiness.route_response(path, cache)[0], 503)
        self.assertEqual(readiness.route_response("/auth/v1/token", cache)[0], 404)

    def test_expired_success_cannot_survive_a_failed_recheck(self):
        reports = iter([{"ready": True, "issues": []}, RuntimeError("private error")])
        def evaluate(_env):
            value = next(reports)
            if isinstance(value, Exception):
                raise value
            return value
        cache = readiness.ReadinessCache({}, evaluate=evaluate, ttl=3)
        with patch.object(readiness.time, "monotonic", side_effect=[0, 0, 2, 4, 4]):
            self.assertTrue(cache.get()["ready"])
            self.assertTrue(cache.get()["ready"])
            report = cache.get()
            self.assertFalse(report["ready"])
            self.assertNotIn("private", json.dumps(report))

    def test_psql_failure_hides_credentials_and_raw_errors(self):
        password = Path(self.temp.name) / "password"
        password.write_text("private-password-value")
        env = {"READINESS_PASSWORD_FILE": str(password), "PGHOST": "postgres", "PGPORT": "5432", "PGUSER": "nightowl_readiness", "PGDATABASE": "nightowl"}
        with patch.object(readiness.subprocess, "run", side_effect=subprocess.CalledProcessError(1, "psql", stderr="private SQL error")) as run:
            result = readiness.database_inventory(env)
            self.assertFalse(result["ready"])
            self.assertNotIn("private", json.dumps(result))
            self.assertNotIn("private-password-value", " ".join(run.call_args.args[0]))
            self.assertEqual(run.call_args.kwargs["env"]["PGUSER"], "nightowl_readiness")


if __name__ == "__main__":
    unittest.main()
