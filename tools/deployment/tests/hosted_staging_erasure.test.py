#!/usr/bin/env python3
"""Offline identity, transport and ambiguous-outcome safeguards for Edge acceptance."""
import contextlib
import copy
import io
import json
import os
from pathlib import Path
import secrets
import shutil
import ssl
import tempfile
from types import SimpleNamespace
import unittest
from unittest.mock import Mock, patch
import uuid

import hosted_staging_acceptance as base
import hosted_staging_erasure as e


class Tests(unittest.TestCase):
    def setUp(self):
        self.directory = Path(tempfile.mkdtemp(prefix="erasure-offline-", dir="/private/tmp"))
        os.chmod(self.directory, 0o700)
        self.run = uuid.uuid4().hex
        self.users = [{"label": label, "id": str(uuid.uuid4()),
            "email": f"nightowl-staging-{self.run}-{label}@example.test", "password": "a" * 43,
            "rows": [], "objects": [], "cleaned": False} for label in ("a", "b")]
        self.api = SimpleNamespace(config={"origin": base.ORIGIN, "anon_key": "nonsecret-offline-key"}, ca_file=None, trace=[])
        self.runner = base.Runner(self.api, self.directory, state={"origin": base.ORIGIN, "run": self.run, "users": self.users})
        self.runner.sessions = {"a": "offline-session-a", "b": "offline-session-b"}
        self.db = Mock()
        self.subject = e.Erasure(self.runner, self.db)
        self.subject.context.update(owner_id=self.users[0]["id"], prepare_started=True,
                                    delete_started=True, receipt=secrets.token_urlsafe(32))

    def tearDown(self):
        shutil.rmtree(self.directory)

    def test_default_has_no_network_or_private_reads_even_resume(self):
        with patch.object(base, "load_config", side_effect=AssertionError), patch.object(e, "Database", side_effect=AssertionError):
            out = io.StringIO()
            with contextlib.redirect_stdout(out):
                self.assertEqual(e.main(["--config-file", "/absent", "--resume-cleanup"]), 0)
            self.assertFalse(json.loads(out.getvalue())["network"])
            self.assertFalse(json.loads(out.getvalue())["private_files_read"])

    def test_foreign_origin_rejected(self):
        self.api.config["origin"] = "https://production.supabase.co"
        with self.assertRaises(base.Failure):
            e.Edge(self.api)

    def test_context_cannot_swap_owner_run_or_add_authority(self):
        for change in ({"owner_id": self.users[1]["id"]}, {"run": "f" * 32}, {"admin": True},
                       {"receipt": "short"}, {"prepare_started": False}, {"owner_id": None}):
            with self.subTest(change=change), self.assertRaises(base.Failure):
                e.validate_context({**self.subject.context, **change}, self.runner.state)

    def test_malformed_actions_fail_before_connection(self):
        with patch.object(e.http.client, "HTTPSConnection", side_effect=AssertionError):
            for options in ({"action": "destroy"}, {"action": "status"}, {"action": None, "receipt": "a" * 43},
                            {"action": "delete", "receipt": "wrong"}, {"action": "prepare", "token": "bad\nheader"}):
                with self.assertRaises(base.Failure):
                    self.subject.edge.request("offline_probe", **options)

    def test_tls_verifies_before_any_credentials_and_connection_failure_is_unsent(self):
        connection = Mock()
        connection.connect.side_effect = ssl.SSLCertVerificationError("private diagnostic")
        with patch.object(e.http.client, "HTTPSConnection", return_value=connection), self.assertRaises(base.Failure) as caught:
            self.subject.edge.request("offline_probe", action="prepare", token="private-session")
        self.assertFalse(caught.exception.request_attempted)
        connection.request.assert_not_called()
        self.assertNotIn("private", str(caught.exception))

    def test_transport_loss_after_write_is_unknown_and_never_retried(self):
        connection = Mock()
        connection.getresponse.side_effect = OSError("private diagnostic")
        with patch.object(e.http.client, "HTTPSConnection", return_value=connection), self.assertRaises(base.Failure) as caught:
            self.subject.edge.request("offline_probe", action="delete", receipt="a" * 43, token="private-session")
        self.assertTrue(caught.exception.request_attempted)
        self.assertEqual(connection.request.call_count, 1)
        self.assertNotIn("private-session", json.dumps(self.api.trace))

    def test_receipt_status_has_no_authorization_header_or_foreign_url(self):
        connection = Mock()
        connection.getresponse.return_value = SimpleNamespace(status=202, read=lambda n: b'{}')
        with patch.object(e.http.client, "HTTPSConnection", return_value=connection) as factory:
            self.subject.edge.request("status_probe", action="status", receipt="a" * 43)
        self.assertEqual(factory.call_args.args[0], base.HOST)
        args, kwargs = connection.request.call_args
        self.assertEqual(args, ("POST", e.EDGE_PATH))
        self.assertNotIn("Authorization", kwargs["headers"])
        self.assertNotIn("service", json.dumps(kwargs["headers"]))

    def test_redirect_is_never_followed(self):
        connection = Mock()
        connection.getresponse.return_value = SimpleNamespace(status=302)
        with patch.object(e.http.client, "HTTPSConnection", return_value=connection), self.assertRaisesRegex(base.Failure, "edge_redirect_refused"):
            self.subject.edge.request("offline_probe")
        self.assertEqual(connection.request.call_count, 1)

    def test_subject_requires_marker_email_and_exact_id_before_edge(self):
        good = {"id": self.users[0]["id"], "email": self.users[0]["email"], "user_metadata": {"nightowl_acceptance_run": self.run}}
        for value in ({**good, "id": self.users[1]["id"]}, {**good, "email": "real@example.com"},
                      {**good, "user_metadata": {"nightowl_acceptance_run": "f" * 32}}):
            with patch.object(self.runner, "request", return_value=base.Response(200, json.dumps(value).encode())), \
                 patch.object(self.subject.edge, "request") as call, self.assertRaises(base.Failure):
                self.subject.delete(self.users[0])
            call.assert_not_called()

    def test_delete_intent_is_private_and_journaled_before_network(self):
        self.subject.context["delete_started"] = False
        def remote(*args, **kwargs):
            disk = base.private_json(self.directory / "erasure-context.json")
            self.assertTrue(disk["delete_started"])
            self.assertEqual(disk["owner_id"], self.users[0]["id"])
            raise base.Failure("lost_response", request_attempted=True)
        with patch.object(self.subject, "verify_identity"), patch.object(self.subject.edge, "request", side_effect=remote), \
             self.assertRaisesRegex(base.Failure, "lost_response"):
            self.subject.delete(self.users[0])

    def test_wrong_completion_identity_never_marks_subject_deleted(self):
        response = base.Response(200, json.dumps({"ok": True, "user_id": self.users[1]["id"]}).encode())
        with patch.object(self.subject, "verify_identity"), patch.object(self.subject.edge, "request", return_value=response), \
             patch.object(self.subject, "completed") as completed, self.assertRaises(base.Failure):
            self.subject.delete(self.users[0])
        completed.assert_not_called()
        self.assertNotIn("auth_delete_started", self.users[0])

    def test_completion_requires_one_matching_job_checkpoints_and_absence(self):
        zero = dict.fromkeys(("auth_users", "auth_identities", "profiles", "posts", "stories", "storage_objects"), 0)
        for value in ({"count": 0, "completed": True, "checkpoints": True},
                      {"count": 1, "completed": False, "checkpoints": True},
                      {"count": 1, "completed": True, "checkpoints": False}):
            self.db.query.return_value = value
            with self.assertRaises(base.Failure):
                self.subject.completed(self.users[0])
        self.db.query.return_value = {"count": 1, "completed": True, "checkpoints": True}
        with patch.object(self.subject, "inventory", return_value={**zero, "storage_objects": 1}), self.assertRaises(base.Failure):
            self.subject.completed(self.users[0])
        self.assertNotIn("auth_delete_started", self.users[0])
        with patch.object(self.subject, "inventory", return_value=zero):
            self.subject.completed(self.users[0])
        self.assertTrue(self.users[0]["auth_delete_started"])
        self.assertIn("begin read only", self.db.query.call_args.args[0])
        self.assertIn("receipt_hash=", self.db.query.call_args.args[0])

    def test_ambiguous_delete_finalizer_never_retries_or_falls_back_to_auth_delete(self):
        cleaned = []
        with patch.object(self.subject, "recover_status", side_effect=base.Failure("receipt_recovery_incomplete")), \
             patch.object(self.subject, "delete") as delete, patch.object(self.subject, "inventory", return_value={}), \
             patch.object(self.runner, "cleanup_user", side_effect=lambda u: cleaned.append(u["label"]) or True):
            self.assertFalse(self.subject.cleanup())
        self.assertEqual(cleaned, ["b"])
        delete.assert_not_called()

    def test_unknown_prepare_finalizer_keeps_subject_for_explicit_recovery(self):
        self.subject.context.update(receipt=None, delete_started=False)
        cleaned = []
        with patch.object(self.subject, "prepare") as prepare, patch.object(self.subject, "delete") as delete, \
             patch.object(self.subject, "inventory", return_value={}), \
             patch.object(self.runner, "cleanup_user", side_effect=lambda u: cleaned.append(u["label"]) or True):
            self.assertFalse(self.subject.cleanup())
        prepare.assert_not_called()
        delete.assert_not_called()
        self.assertEqual(cleaned, ["b"])

    def test_explicit_resume_revalidates_and_logs_in_before_retrying_only_owner(self):
        calls = []
        with patch.object(self.subject, "recover_status", side_effect=base.Failure("receipt_recovery_incomplete")), \
             patch.object(self.subject, "verify_identity", side_effect=lambda u: calls.append(("verify", u["label"]))), \
             patch.object(self.subject, "restore_session", side_effect=lambda u: calls.append(("login", u["label"]))), \
             patch.object(self.subject, "delete", side_effect=lambda u: calls.append(("delete", u["label"]))), \
             patch.object(self.subject, "inventory", return_value={}), patch.object(self.runner, "cleanup_user", return_value=True):
            self.assertTrue(self.subject.cleanup(resume=True))
        self.assertEqual(calls, [("verify", "a"), ("login", "a"), ("delete", "a")])

    def test_erased_success_allows_cleanup_only_after_receipt_proof(self):
        calls = []
        with patch.object(self.subject, "recover_status", side_effect=lambda u: calls.append("receipt")), \
             patch.object(self.subject, "inventory", return_value={}), \
             patch.object(self.runner, "cleanup_user", side_effect=lambda u: calls.append("cleanup_" + u["label"]) or True):
            self.assertTrue(self.subject.cleanup())
        self.assertEqual(calls, ["receipt", "cleanup_a", "cleanup_b"])

    def test_inventory_cannot_accept_foreign_identity(self):
        foreign = copy.deepcopy(self.users[0])
        foreign["id"] = str(uuid.uuid4())
        with self.assertRaises(base.Failure):
            self.subject.inventory(foreign)
        self.db.query.assert_not_called()


if __name__ == "__main__":
    unittest.main()
