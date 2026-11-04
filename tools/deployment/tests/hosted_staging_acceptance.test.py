"""Offline tests only: dummy credentials, fake HTTP, and private tempfiles."""
import base64
import contextlib
import importlib.util
import io
import json
import os
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch
import uuid
from urllib.parse import parse_qs, urlsplit

SPEC = importlib.util.spec_from_file_location("hosted_acceptance", Path(__file__).with_name("hosted_staging_acceptance.py"))
m = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(m)


def jwt(role, ref=m.REF):
    def encoded(value):
        return base64.urlsafe_b64encode(json.dumps(value).encode()).decode().rstrip("=")
    return encoded({"alg": "HS256", "typ": "JWT"}) + "." + encoded({"role": role, "ref": ref}) + "." + base64.urlsafe_b64encode(bytes(32)).decode().rstrip("=")


def reply(status, data=None, binary=None):
    return m.Response(status, binary if binary is not None else json.dumps(data).encode())


class FakeApi:
    def __init__(self, *, corrupt=False, fail_creation=False, wrong_publication=False,
                 missing_owner_read=False, wrong_refresh=False, allow_foreign_reference=False,
                 moderation_status=403, allow_self_approval=False, cleanup_noop=False, stale_old_url=False,
                 hide_list_metadata=False):
        self.users, self.rows, self.objects, self.trace, self.calls = {}, {}, {}, [], []
        self.corrupt, self.fail_creation, self.mutated = corrupt, fail_creation, False
        self.wrong_publication, self.missing_owner_read = wrong_publication, missing_owner_read
        self.wrong_refresh, self.allow_foreign_reference = wrong_refresh, allow_foreign_reference
        self.moderation_status, self.allow_self_approval, self.cleanup_noop = moderation_status, allow_self_approval, cleanup_noop
        self.stale_old_url, self.cached_objects = stale_old_url, {}
        self.hide_list_metadata = hide_list_metadata

    def request(self, stage, path, *, method="GET", token=None, service=False, data=None, binary=None, mime=None, headers=None):
        self.calls.append((stage, path, method, token, service, data))
        if service:
            assert path.startswith("/auth/v1/admin/users")
        uid = token.removeprefix("session-") if token else None
        parts, query = urlsplit(path), parse_qs(urlsplit(path).query)
        route = parts.path
        if route == "/auth/v1/admin/users" and method == "POST":
            assert service
            uid = str(uuid.uuid4())
            self.users[uid] = {"id": uid, **data}
            if self.fail_creation:
                raise m.Failure("transport_failure")
            return reply(200, {"id": uid})
        if route.startswith("/auth/v1/admin/users/"):
            assert service
            target = route.rsplit("/", 1)[1]
            if target not in self.users:
                return reply(404, {})
            if method == "DELETE":
                del self.users[target]
                return reply(200, {})
            return reply(200, self.users[target])
        if route == "/auth/v1/token":
            if query.get("grant_type") == ["refresh_token"]:
                uid = data["refresh_token"].removeprefix("refresh-")
                return reply(200, {"user": {"id": str(uuid.uuid4()) if self.wrong_refresh else uid},
                                   "access_token": "session-" + uid})
            user = next((u for u in self.users.values() if u["email"] == data["email"] and u["password"] == data["password"]), None)
            return reply(200, {"user": {"id": user["id"]}, "access_token": "session-" + user["id"],
                               "refresh_token": "refresh-" + user["id"]}) if user else reply(400, {})
        if route == "/auth/v1/user":
            return reply(200, {"id": uid}) if uid in self.users else reply(401, {})
        if route == "/rest/v1/rpc/social_active":
            return reply(200, uid in self.users)
        if route.startswith("/rest/v1/"):
            table = route.rsplit("/", 1)[1]
            target = query.get("id", [""])[0].removeprefix("eq.")
            if method == "GET" and query.get("limit") == ["0"]:
                return reply(200, [])
            if table == "profiles":
                return reply(200, [{"id": uid, "moderation_status": "pending"}] if target == uid else [])
            if method == "POST":
                referenced = data["media_url"].split("/storage/v1/object/public/")[-1]
                if referenced not in self.objects:
                    return reply(400, {})
                if data["user_id"] != uid or f"/{uid}/" not in data["media_url"] and not self.allow_foreign_reference:
                    return reply(403, {})
                row = {**data, "moderation_status": "pending"}
                self.rows[(table, row["id"])] = row
                return reply(201, [{**row, "id": str(uuid.uuid4())} if self.wrong_publication else row])
            row = self.rows.get((table, target))
            if method == "PATCH":
                assert headers == {"Prefer": "return=representation"}
                if self.allow_self_approval and row:
                    row["moderation_status"] = "approved"
                return reply(self.moderation_status, [] if self.moderation_status == 200 else {})
            if method == "DELETE":
                if row and row["user_id"] == uid and query.get("user_id") == ["eq." + uid]:
                    del self.rows[(table, target)]
                return reply(204)
            if self.missing_owner_read and row and row["user_id"] == uid:
                return reply(200, [])
            return reply(200, [row] if row and row["user_id"] == uid else [])
        tail = route.removeprefix("/storage/v1/object/")
        if tail.startswith("list/"):
            assert method == "POST" and data["limit"] == 100 and data["offset"] == 0
            if self.hide_list_metadata:
                return reply(200, [])
            bucket = tail.removeprefix("list/")
            prefix = bucket + "/" + data["prefix"] + "/"
            return reply(200, [{"name": key.removeprefix(prefix)} for key, value in self.objects.items()
                               if key.startswith(prefix) and value[0] == uid])
        if tail.startswith("public/"):
            return reply(400, {})
        if tail.startswith("authenticated/"):
            if "nightowl_probe" in query:
                assert headers == {"Cache-Control": "no-cache"}
                assert len(query["nightowl_probe"]) == 1 and m.re.fullmatch(r"[0-9a-f]{32}", query["nightowl_probe"][0])
            key = tail.removeprefix("authenticated/")
            value = self.objects.get(key)
            if self.stale_old_url and "nightowl_probe" not in query:
                value = self.cached_objects.get(key, value)
            if value and value[0] == uid:
                body = value[1]
                if self.corrupt and self.mutated and not (self.stale_old_url and "nightowl_probe" not in query):
                    body = bytes([body[0] ^ 1]) + body[1:]
                return reply(200, binary=body)
            return reply(400, {})
        if tail.startswith("sign/"):
            key = tail.removeprefix("sign/")
            value = self.objects.get(key)
            if method == "GET" and query.get("token") == ["dummy-signed-capability"] and value:
                return reply(200, binary=value[1])
            if value and value[0] == uid:
                return reply(200, {"signedURL": "/object/sign/" + key + "?token=dummy-signed-capability"})
            return reply(400, {})
        if method == "DELETE":
            for name in data["prefixes"]:
                key = tail + "/" + name
                if any(r["media_url"].endswith("/" + key) for r in self.rows.values()):
                    return reply(403, {})
                if not self.cleanup_noop and key in self.objects and self.objects[key][0] == uid:
                    del self.objects[key]
            return reply(200, [])
        if method == "PUT" or tail in self.objects:
            self.mutated = True
            return reply(403, {})
        owner = tail.split("/")[1]
        if uid != owner:
            return reply(403, {})
        self.objects[tail] = (uid, binary)
        self.cached_objects[tail] = (uid, binary)
        return reply(200, {})


class AcceptanceTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix="nightowl-acceptance-test-", dir="/private/tmp")
        self.directory = Path(self.temp.name)
        os.chmod(self.directory, 0o700)
        self.no_network = patch.object(m.http.client, "HTTPSConnection", side_effect=AssertionError("unexpected network"))
        self.no_network.start()

    def tearDown(self):
        self.no_network.stop()
        self.temp.cleanup()

    def config(self, **changes):
        value = {"origin": m.ORIGIN, "anon_key": jwt("anon"), "service_role_key": jwt("service_role"), **changes}
        path = self.directory / "api.json"
        path.write_text(json.dumps(value))
        path.chmod(0o600)
        return path

    def test_default_reads_no_config_and_makes_no_network_calls(self):
        out = io.StringIO()
        with patch.object(m, "load_config", side_effect=AssertionError("private read")), contextlib.redirect_stdout(out):
            with patch.object(m.ssl, "create_default_context", side_effect=AssertionError("CA read")):
                self.assertEqual(m.main(["--config-file", "/nonexistent", "--ca-file", "/absent-ca", "--cleanup-only"]), 0)
        self.assertEqual(json.loads(out.getvalue())["status"], "offline_plan")

    def test_exact_staging_config(self):
        self.assertEqual(m.load_config(self.config())["origin"], m.ORIGIN)

    def test_production_lookalike_and_extra_fields_rejected(self):
        for origin in ["https://jbbdnpsvstwxtgtjoeru.supabase.co", m.ORIGIN + "/", m.ORIGIN + ".invalid", "http://" + m.HOST]:
            with self.subTest(origin=origin), self.assertRaises(m.Failure):
                m.load_config(self.config(origin=origin))
        with self.assertRaises(m.Failure):
            m.load_config(self.config(password="dummy"))

    def test_key_role_ref_shape_and_unicode_rejected(self):
        for key in [jwt("anon"), jwt("service_role", "jbbdnpsvstwxtgtjoeru"), "https://example.invalid", "abc:def", "a\\b", "юникод"]:
            with self.subTest(key=key[:12]), self.assertRaises(m.Failure):
                m.validate_key(key, "service_role")

    def test_permissions_symlinks_and_parent_traversal_rejected(self):
        path = self.config()
        path.chmod(0o644)
        with self.assertRaises(m.Failure):
            m.load_config(path)
        path.chmod(0o600)
        link = self.directory / "link"
        link.symlink_to(path)
        with self.assertRaises(m.Failure):
            m.load_config(link)
        with self.assertRaises(m.Failure):
            m.private_path(self.directory / "child/../api.json")

    def test_other_git_checkouts_and_worktree_git_files_rejected(self):
        checkout = self.directory / "other-checkout"
        checkout.mkdir(mode=0o700)
        (checkout / ".git").mkdir()
        with self.assertRaisesRegex(m.Failure, "private_path_inside_git_checkout"):
            m.private_path(checkout / "new-run", exists=False)
        (checkout / ".git").rmdir()
        (checkout / ".git").write_text("gitdir: /dummy/worktrees/test\n")
        with self.assertRaisesRegex(m.Failure, "private_path_inside_git_checkout"):
            m.private_path(checkout / "new-run", exists=False)

    def test_signed_url_cannot_redirect_credentials(self):
        expected = "/storage/v1/object/sign/posts/owner/a.png?token=dummy"
        self.assertEqual(m.signed_path("/object/sign/posts/owner/a.png?token=dummy", "posts", "owner/a.png"), expected)
        for value in ["https://example.invalid" + expected, "//example.invalid" + expected, m.ORIGIN + ":443" + expected,
                      expected + "&token=second", expected + "#fragment", expected.replace("owner", "other")]:
            with self.subTest(value=value), self.assertRaises(m.Failure):
                m.signed_path(value, "posts", "owner/a.png")

    def test_service_role_cannot_reach_app_or_storage(self):
        api = m.Api(m.load_config(self.config()), execute=True)
        for path in ["/storage/v1/object/posts", "/rest/v1/posts"]:
            with self.assertRaisesRegex(m.Failure, "service_role_outside_synthetic_auth"):
                api.request("test", path, service=True)

    def test_redirect_refused_without_second_request_and_error_sanitized(self):
        class Connection:
            calls = 0
            def __init__(self, *args, **kwargs):
                assert args == (m.HOST,) and kwargs["port"] == 443
            def request(self, *args, **kwargs):
                Connection.calls += 1
            def connect(self):
                pass
            def getresponse(self):
                return type("Reply", (), {"status": 302})()
            def close(self):
                pass
        api = m.Api(m.load_config(self.config()), execute=True)
        with patch.object(m.http.client, "HTTPSConnection", Connection), self.assertRaisesRegex(m.Failure, "redirect_refused"):
            api.request("test", "/auth/v1/user")
        self.assertEqual(Connection.calls, 1)

    def test_explicit_ca_keeps_certificate_and_hostname_verification(self):
        context = m.ssl.SSLContext(m.ssl.PROTOCOL_TLS_CLIENT)
        observed = []
        class Connection:
            def __init__(self, host, **kwargs):
                observed.append((host, kwargs))
                self.connected = False
            def connect(self):
                self.connected = True
            def request(self, *args, **kwargs):
                assert self.connected
            def getresponse(self):
                return type("Reply", (), {"status": 200, "read": lambda self, limit: b"{}"})()
            def close(self):
                pass
        ca_path = str(self.directory / "public-roots.pem")
        api = m.Api(m.load_config(self.config()), execute=True, ca_file=ca_path)
        with patch.object(m.ssl, "create_default_context", return_value=context) as create, patch.object(m.http.client, "HTTPSConnection", Connection):
            self.assertEqual(api.request("test", "/auth/v1/user").status, 200)
        create.assert_called_once_with(cafile=ca_path)
        self.assertEqual(observed[0][0], m.HOST)
        self.assertEqual(observed[0][1]["port"], 443)
        self.assertIs(observed[0][1]["context"], context)
        self.assertEqual(context.verify_mode, m.ssl.CERT_REQUIRED)
        self.assertTrue(context.check_hostname)

    def test_insecure_context_is_refused_without_http(self):
        context = m.ssl.SSLContext(m.ssl.PROTOCOL_TLS_CLIENT)
        context.check_hostname = False
        context.verify_mode = m.ssl.CERT_NONE
        api = m.Api(m.load_config(self.config()), execute=True, ca_file="/public-ca")
        with patch.object(m.ssl, "create_default_context", return_value=context), self.assertRaisesRegex(m.Failure, "tls_verification_required") as caught:
            api.request("test", "/auth/v1/user")
        self.assertIs(caught.exception.request_attempted, False)

    def test_missing_ca_has_no_fallback_or_http(self):
        api = m.Api(m.load_config(self.config()), execute=True, ca_file=str(self.directory / "missing.pem"))
        with self.assertRaisesRegex(m.Failure, "tls_ca_load_failed") as caught:
            api.request("test", "/auth/v1/user")
        self.assertIs(caught.exception.request_attempted, False)

    def test_tls_failure_precedes_http_and_does_not_leave_uncertain_creation(self):
        class Connection:
            requests = 0
            def __init__(self, *args, **kwargs):
                pass
            def connect(self):
                raise m.ssl.SSLCertVerificationError(20, "dummy-secret-error-text")
            def request(self, *args, **kwargs):
                Connection.requests += 1
            def close(self):
                pass
        api = m.Api(m.load_config(self.config()), execute=True)
        runner = m.Runner(api, self.directory)
        with patch.object(m.http.client, "HTTPSConnection", Connection), self.assertRaisesRegex(m.Failure, "tls_verification_before_http"):
            runner.make_user("a")
        self.assertEqual(Connection.requests, 0)
        self.assertFalse(runner.state["users"][0]["creation_uncertain"])
        self.assertTrue(runner.cleanup())
        self.assertFalse(api.trace[-1]["http_request_attempted"])
        self.assertNotIn("dummy-secret-error-text", json.dumps(api.trace))

    def test_lost_response_is_an_unknown_request_outcome(self):
        class Connection:
            def __init__(self, *args, **kwargs):
                pass
            def connect(self):
                pass
            def request(self, *args, **kwargs):
                pass
            def getresponse(self):
                raise m.http.client.RemoteDisconnected("dummy-secret-error-text")
            def close(self):
                pass
        api = m.Api(m.load_config(self.config()), execute=True)
        runner = m.Runner(api, self.directory)
        with patch.object(m.http.client, "HTTPSConnection", Connection), self.assertRaisesRegex(m.Failure, "transport_failure_request_outcome_unknown"):
            runner.make_user("a")
        self.assertTrue(runner.state["users"][0]["creation_uncertain"])
        self.assertFalse(runner.cleanup())
        self.assertTrue(api.trace[-1]["http_request_attempted"])
        self.assertNotIn("dummy-secret-error-text", json.dumps(api.trace))

    def test_complete_fake_flow_only_synthetic_cleanup_and_private_receipt(self):
        api = FakeApi()
        runner = m.Runner(api, self.directory)
        runner.exercise()
        self.assertTrue(runner.cleanup())
        self.assertFalse(api.users or api.rows or api.objects)
        self.assertGreater(len(runner.report["checks"]), 40)
        self.assertEqual((self.directory / "synthetic-state.json").stat().st_mode & 0o777, 0o600)
        raw = json.dumps(runner.report)
        for user in runner.state["users"]:
            self.assertNotIn(user["email"], raw)
            self.assertNotIn(user["password"], raw)
            self.assertNotIn(user["id"], raw)
        self.assertNotIn("dummy-signed-capability", raw)
        self.assertTrue(all(path.startswith("/auth/v1/admin/users") for _, path, _, _, service, _ in api.calls if service))

    def test_same_size_corruption_after_denied_write_fails(self):
        runner = m.Runner(FakeApi(corrupt=True), self.directory)
        with self.assertRaisesRegex(m.Failure, "denied_mutations_preserve_bytes"):
            runner.exercise()
        self.assertTrue(runner.cleanup())

    def test_wrong_refresh_identity_fails(self):
        runner = m.Runner(FakeApi(wrong_refresh=True), self.directory)
        with self.assertRaisesRegex(m.Failure, "token_refresh_identity_a"):
            runner.make_user("a")
        self.assertTrue(runner.cleanup())

    def test_wrong_returned_row_or_missing_owner_row_fails_before_privacy_checks(self):
        for option, failure in [("wrong_publication", "pending_publication"), ("missing_owner_read", "owner_publication_identity")]:
            with self.subTest(option=option):
                api = FakeApi(**{option: True})
                runner = m.Runner(api, self.directory)
                with self.assertRaisesRegex(m.Failure, failure):
                    runner.exercise()
                self.assertFalse(any(stage == "pending_visibility" for stage, *_ in api.calls))
                self.assertTrue(runner.cleanup())

    def test_existing_foreign_reference_is_denied_not_merely_missing_media(self):
        api = FakeApi(allow_foreign_reference=True)
        runner = m.Runner(api, self.directory)
        with self.assertRaisesRegex(m.Failure, "foreign_media_reference_accepted"):
            runner.exercise()
        calls = [(path, data) for stage, path, _, _, _, data in api.calls if stage == "foreign_media_publication"]
        self.assertEqual(len(calls), 1)
        referenced = calls[0][1]["media_url"].split("/storage/v1/object/public/")[-1]
        self.assertIn(referenced, api.objects)
        self.assertTrue(runner.cleanup())

    def test_moderation_zero_row_200_or_204_requires_unchanged_owner_row(self):
        for status in (200, 204):
            with self.subTest(status=status):
                api = FakeApi(moderation_status=status)
                runner = m.Runner(api, self.directory)
                runner.exercise()
                self.assertTrue(runner.cleanup())
                self.assertEqual(sum(check.startswith("self_approval_blocked_") for check in runner.report["checks"]), 4)

    def test_mutant_actual_approval_fails_even_with_empty_or_204_response(self):
        for status in (200, 204, 403):
            with self.subTest(status=status):
                api = FakeApi(moderation_status=status, allow_self_approval=True)
                runner = m.Runner(api, self.directory)
                with self.assertRaisesRegex(m.Failure, "self_approval_blocked_a_posts"):
                    runner.exercise()
                self.assertTrue(runner.cleanup())

    def test_cleanup_readable_bytes_fail_with_sanitized_diagnostics(self):
        api = FakeApi(cleanup_noop=True)
        runner = m.Runner(api, self.directory, keep=True)
        runner.exercise()
        self.assertFalse(runner.cleanup())
        self.assertTrue(all(item["code"] == "cleanup_object_metadata_still_present" for item in runner.report["cleanup_failures"]))
        self.assertEqual(len(runner.report["cleanup_observations"]), 2)
        for observation in runner.report["cleanup_observations"]:
            self.assertEqual(set(observation), {"account", "bucket", "delete_status", "delete_count", "metadata_status", "metadata_match_count", "verification_status"})
            self.assertEqual(observation["delete_status"], 200)
            self.assertEqual(observation["delete_count"], 0)
            self.assertEqual(observation["metadata_status"], 200)
            self.assertEqual(observation["metadata_match_count"], 1)
            self.assertEqual(observation["verification_status"], 200)
        raw = json.dumps(runner.report)
        for user in runner.state["users"]:
            for secret in (user["id"], user["email"], user["password"]):
                self.assertNotIn(secret, raw)
        self.assertFalse(any(method == "DELETE" and path.startswith("/auth/") for _, path, method, *_ in api.calls))

    def test_cached_old_bytes_cannot_hide_fresh_overwrite(self):
        api = FakeApi(stale_old_url=True, corrupt=True)
        runner = m.Runner(api, self.directory)
        with self.assertRaisesRegex(m.Failure, "denied_mutations_preserve_bytes_a_posts"):
            runner.exercise()
        key, (owner, original) = next(iter(api.cached_objects.items()))
        old = api.request("test", "/storage/v1/object/authenticated/" + key, token="session-" + owner)
        self.assertEqual(old.body, original)
        fresh_reads = [path for stage, path, *_ in api.calls if stage.startswith(("owner_download_", "denied_mutations_preserve_bytes_"))]
        self.assertTrue(all("?nightowl_probe=" in path for path in fresh_reads))
        self.assertEqual(len(fresh_reads), len(set(fresh_reads)))
        self.assertTrue(runner.cleanup())

    def test_metadata_absence_cannot_override_still_readable_fresh_bytes(self):
        api = FakeApi(cleanup_noop=True, hide_list_metadata=True)
        runner = m.Runner(api, self.directory, keep=True)
        runner.exercise()
        self.assertFalse(runner.cleanup())
        self.assertTrue(all(item["code"] == "cleanup_object_still_readable" for item in runner.report["cleanup_failures"]))
        self.assertTrue(all(item["metadata_match_count"] == 0 and item["verification_status"] == 200
                            for item in runner.report["cleanup_observations"]))
        self.assertFalse(any(method == "DELETE" and path.startswith("/auth/") for _, path, method, *_ in api.calls))

    def test_stale_old_url_does_not_block_fresh_metadata_and_byte_cleanup(self):
        api = FakeApi(stale_old_url=True)
        runner = m.Runner(api, self.directory)
        runner.exercise()
        self.assertTrue(runner.cleanup())
        self.assertFalse(api.users or api.objects or api.rows)
        self.assertTrue(all(item["metadata_match_count"] == 0 and item["verification_status"] == 400
                            for item in runner.report["cleanup_observations"]))
        key, (owner, original) = next(iter(api.cached_objects.items()))
        self.assertEqual(api.request("test", "/storage/v1/object/authenticated/" + key, token="session-" + owner).body, original)
        verification = [path for stage, path, *_ in api.calls if stage == "cleanup_object_verify"]
        self.assertTrue(all("?nightowl_probe=" in path for path in verification))
        self.assertEqual(len(verification), len(set(verification)))

    def test_creation_response_loss_requires_private_journal_review(self):
        runner = m.Runner(FakeApi(fail_creation=True), self.directory)
        with self.assertRaisesRegex(m.Failure, "transport_failure"):
            runner.make_user("a")
        self.assertFalse(runner.cleanup())
        self.assertFalse(any(method == "DELETE" for _, _, method, _, _, _ in runner.api.calls))

    def test_resume_cleanup_uses_fresh_user_jwt_and_checks_auth_marker(self):
        api = FakeApi()
        runner = m.Runner(api, self.directory, keep=True)
        runner.exercise()
        state = m.private_json(self.directory / "synthetic-state.json")
        resumed = m.Runner(api, self.directory, state=state)
        self.assertTrue(resumed.cleanup())
        self.assertTrue(any(stage == "cleanup_login" for stage, *_ in api.calls))
        self.assertFalse(api.users or api.objects or api.rows)

    def test_forged_journal_or_changed_auth_marker_never_deletes(self):
        api = FakeApi()
        runner = m.Runner(api, self.directory)
        user = runner.make_user("a")
        api.users[user["id"]]["user_metadata"]["nightowl_acceptance_run"] = "different"
        self.assertFalse(runner.cleanup())
        self.assertFalse(any(method == "DELETE" for _, _, method, _, _, _ in api.calls))
        user["objects"].append({"bucket": "posts", "name": user["id"] + "/other-run/file.png"})
        with self.assertRaisesRegex(m.Failure, "invalid_cleanup_object"):
            m.validate_journal(runner.state)

    def test_existing_workdir_is_not_overwritten(self):
        config = self.config()
        existing = self.directory / "already-exists"
        existing.mkdir(mode=0o700)
        marker = existing / "marker"
        marker.write_text("preserve")
        with contextlib.redirect_stdout(io.StringIO()):
            self.assertEqual(m.main(["--execute", "--config-file", str(config), "--workdir", str(existing)]), 1)
        self.assertEqual(marker.read_text(), "preserve")

    def test_original_fixtures_are_small_and_pinned(self):
        image, video = m.fixtures()
        self.assertTrue(image[4].startswith(b"\x89PNG\r\n\x1a\n"))
        self.assertEqual(video[4][4:8], b"ftyp")
        self.assertLess(len(image[4]) + len(video[4]), 2048)


if __name__ == "__main__":
    unittest.main(verbosity=2)
