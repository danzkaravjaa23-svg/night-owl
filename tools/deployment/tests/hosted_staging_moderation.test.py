#!/usr/bin/env python3
"""Offline safeguards and failure propagation for the opt-in moderation runner."""
import contextlib
import io
import json
import os
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch
import uuid
from types import SimpleNamespace

import hosted_staging_acceptance as base
import hosted_staging_moderation as m


def synthetic(run, label="a"):
    return {"id": str(uuid.uuid4()), "label": label,
            "email": f"nightowl-staging-{run}-{label}@example.test", "password": "a" * 43,
            "rows": [], "objects": [], "cleaned": False}


class Tests(unittest.TestCase):
    def setUp(self):
        self.parent = Path(tempfile.mkdtemp(prefix="moderation-offline-", dir="/private/tmp"))
        os.chmod(self.parent, 0o700)
        self.run = uuid.uuid4().hex
        self.user = synthetic(self.run)

    def tearDown(self):
        import shutil
        shutil.rmtree(self.parent)

    def private(self, name, text):
        path = self.parent / name
        path.write_text(text)
        path.chmod(0o600)
        return path

    def service(self, **changes):
        values = {"host": m.POOLER, "port": "5432", "dbname": "postgres", "user": f"postgres.{base.REF}",
                  "sslmode": "verify-full", "sslrootcert": str(self.parent / "ca.pem"), **changes}
        return self.private("service.conf", "[nightowl_staging]\n" + "".join(f"{k}={v}\n" for k, v in values.items()))

    def db(self, **changes):
        ca = self.private("ca.pem", "offline fixture")
        psql = self.private("psql", "#!/bin/sh\nexit 1\n")
        psql.chmod(0o700)
        return m.Database(self.service(**changes), self.private("pgpass", "private offline fixture"), psql)

    def test_default_reads_nothing_and_makes_no_network(self):
        with patch.object(base, "load_config", side_effect=AssertionError), patch.object(m, "Database", side_effect=AssertionError):
            out = io.StringIO()
            with contextlib.redirect_stdout(out):
                self.assertEqual(m.main(["--config-file", "/absent", "--cleanup-only"]), 0)
            self.assertFalse(json.loads(out.getvalue())["private_files_read"])

    def test_database_requires_exact_project_and_verified_tls(self):
        for override in ({"user": "postgres.other"}, {"host": "evil.example"}, {"sslmode": "require"},
                         {"dbname": "other"}, {"options": "-c role=service_role"}, {"hostaddr": "1.2.3.4"}):
            with self.subTest(override=override), self.assertRaises(base.Failure):
                self.db(**override)

    def test_private_permissions_enforced(self):
        db = self.db()
        db.passfile.chmod(0o644)
        with self.assertRaises(base.Failure):
            m.Database(db.service_file, db.passfile, db.psql)

    def test_sql_identity_cannot_target_existing_account_or_inject(self):
        good = m.identity_predicate(self.user, self.run)
        self.assertIn("raw_user_meta_data->>'nightowl_acceptance_run'", good)
        for field, value in (("email", "real@example.com"), ("id", "' or true--"), ("label", "admin")):
            with self.subTest(field=field), self.assertRaises(base.Failure):
                m.identity_predicate({**self.user, field: value}, self.run)

    def test_context_rejects_cross_run_duplicate_and_invalid_ids(self):
        good = {"member_run": self.run, "moderator_run": "b" * 32, "messages": [str(uuid.uuid4())], "audits": []}
        m.validate_context(good, self.run, "b" * 32)
        for bad in ({**good, "member_run": "c" * 32}, {**good, "messages": good["messages"] * 2},
                    {**good, "messages": ["' or true--"]}, {**good, "extra": True}):
            with self.assertRaises(base.Failure):
                m.validate_context(bad, self.run, "b" * 32)

    def test_db_error_never_discloses_diagnostics(self):
        db = self.db()
        class Result:
            returncode, stdout, stderr = 1, "", "password=private must never escape"
        with patch.object(m.subprocess, "run", return_value=Result()), self.assertRaisesRegex(base.Failure, "^database_statement_failed$"):
            db.query("select 1")

    def test_db_uses_service_and_stdin_not_secret_arguments(self):
        db = self.db()
        class Result:
            returncode, stdout, stderr = 0, '{"changed":1,"admin":true,"banned":false}', ""
        with patch.dict(os.environ, {"PGPASSWORD": "ambient-secret", "PGHOST": "evil"}), \
             patch.object(m.subprocess, "run", return_value=Result()) as run:
            db.flags(self.user, self.run, admin=True)
        args, kwargs = run.call_args
        self.assertNotIn("ambient-secret", json.dumps(args))
        self.assertNotIn("PGPASSWORD", kwargs["env"])
        self.assertNotIn("PGHOST", kwargs["env"])
        self.assertIn("--dbname=service=nightowl_staging", args[0])
        self.assertIn("Synthetic identity mismatch", kwargs["input"])

    def test_database_origin_mismatch_fails(self):
        db = self.db()
        with patch.object(db, "query", return_value={"origin": "https://other.supabase.co"}), self.assertRaises(base.Failure):
            db.preflight()

    def test_review_receipt_is_bound_to_target_version_decision_and_audit(self):
        runner = object.__new__(m.Moderation)
        runner.report = {"checks": []}
        runner.record_audit = lambda *args: None
        target, version, audit = (str(uuid.uuid4()) for _ in range(3))
        good = {"target_id": target, "target_type": "post", "review_version": version,
                "status": "approved", "audit_id": audit}
        runner.rpc = lambda *args: base.Response(200, json.dumps(good).encode())
        runner.review("post", target, version, "approved", "session")
        for field, value in (("target_id", str(uuid.uuid4())), ("review_version", str(uuid.uuid4())),
                             ("status", "rejected"), ("audit_id", None)):
            runner.rpc = lambda *args: base.Response(200, json.dumps({**good, field: value}).encode())
            with self.assertRaises(base.Failure):
                runner.review("post", target, version, "approved", "session")

    def test_ban_receipt_must_resolve_exact_selected_report(self):
        runner = object.__new__(m.Moderation)
        runner.report = {"checks": []}
        runner.record_audit = lambda *args: None
        target, report, audit = (str(uuid.uuid4()) for _ in range(3))
        good = {"target_id": target, "target_type": "user", "action": "ban_user",
                "report_id": report, "report_status": "resolved", "audit_id": audit}
        runner.rpc = lambda *args: base.Response(200, json.dumps(good).encode())
        runner.action("ban_user", target, "session", report)
        runner.rpc = lambda *args: base.Response(200, json.dumps({**good, "report_id": None}).encode())
        with self.assertRaises(base.Failure):
            runner.action("ban_user", target, "session", report)

    def test_cleanup_does_not_remove_auth_before_scoped_context(self):
        class Db:
            def cleanup_context(self, *args):
                raise base.Failure("synthetic_context_cleanup_incomplete")
        runner = object.__new__(m.Moderation)
        empty = SimpleNamespace(state={"origin": base.ORIGIN, "run": self.run, "users": []})
        runner.db, runner.members, runner.moderator, runner.context, runner.report = Db(), empty, empty, {}, {}
        self.assertFalse(runner.cleanup())
        self.assertEqual(runner.report["cleanup_failure"], "synthetic_context_cleanup_incomplete")


    def resume_runner(self, status, body=None):
        user = {**self.user, "auth_delete_started": True}
        state = {"origin": base.ORIGIN, "run": self.run, "users": [user]}
        calls = []
        child = SimpleNamespace(state=state,
            request=lambda stage, path, **kwargs: (calls.append((stage, path, kwargs)) or
                base.Response(status, json.dumps(body).encode())),
            journal=lambda: calls.append("journal"))
        empty = SimpleNamespace(state={"origin": base.ORIGIN, "run": "b" * 32, "users": []})
        runner = object.__new__(m.Moderation)
        runner.members, runner.moderator = child, empty
        return runner, user, calls

    def test_ambiguous_auth_delete_404_reconciled_before_database_guard(self):
        runner, user, calls = self.resume_runner(404)
        runner.reconcile_completed_auth()
        self.assertTrue(user["cleaned"])
        self.assertEqual(calls[-1], "journal")
        self.assertEqual(calls[0][1], f"/auth/v1/admin/users/{user['id']}")
        self.assertEqual(calls[0][2], {"service": True})
        db = self.db()
        context = {"member_run": self.run, "moderator_run": "b" * 32, "messages": [], "audits": []}
        with patch.object(db, "query", side_effect=AssertionError("Already removed identity cannot block SQL guard")):
            self.assertEqual(db.cleanup_context(runner.members, runner.moderator, context), {"messages": 0, "reports": 0})

    def test_ambiguous_auth_delete_present_identity_keeps_exact_marker_guard(self):
        body = {"id": self.user["id"], "email": self.user["email"],
                "user_metadata": {"nightowl_acceptance_run": self.run}}
        runner, user, calls = self.resume_runner(200, body)
        runner.reconcile_completed_auth()
        self.assertFalse(user["cleaned"])
        self.assertNotIn("journal", calls)
        for bad in ({**body, "email": "real@example.com"}, {**body, "user_metadata": {}}, {**body, "id": str(uuid.uuid4())}):
            runner, user, calls = self.resume_runner(200, bad)
            with self.assertRaisesRegex(base.Failure, "cleanup_resume_identity_mismatch"):
                runner.reconcile_completed_auth()
            self.assertFalse(user["cleaned"])

    def test_missing_auth_without_started_delete_cannot_be_marked_cleaned(self):
        runner, user, calls = self.resume_runner(404)
        user["auth_delete_started"] = False
        runner.reconcile_completed_auth()
        self.assertFalse(user["cleaned"])
        self.assertEqual(calls, [])


    def test_revocation_commits_and_is_reported_even_if_context_deletion_fails(self):
        calls = []
        class Db:
            def flags(self, user, run, **kwargs):
                calls.append((user["label"], kwargs))
            def cleanup_context(self, *args):
                calls.append("context")
                raise base.Failure("database_statement_failed")
        child = SimpleNamespace(state={"origin": base.ORIGIN, "run": self.run, "users": [self.user]})
        empty = SimpleNamespace(state={"origin": base.ORIGIN, "run": "b" * 32, "users": []})
        runner = object.__new__(m.Moderation)
        runner.db, runner.members, runner.moderator, runner.context, runner.report = Db(), empty, child, {}, {}
        self.assertFalse(runner.cleanup())
        self.assertEqual(calls, [("a", {"admin": False, "banned": False}), "context"])
        self.assertTrue(runner.report["synthetic_privilege_revocations"][0]["confirmed"])

    def test_audit_missing_or_wrong_identity_cannot_pass_aggregate_proof(self):
        db = self.db()
        moderator = SimpleNamespace(state={"users": [self.user]})
        context = {"audits": [{"id": str(uuid.uuid4()), "action": "ban_user", "target_type": "user", "target_id": str(uuid.uuid4())}]}
        with patch.object(db, "query", return_value={"count": 1, "expected": 1, "matched": 0}) as query:
            with self.assertRaisesRegex(base.Failure, "audit_receipt_not_persisted"):
                db.audit_receipts(moderator, context)
        sql = query.call_args.args[0]
        self.assertIn("a.actor_id=", sql)
        self.assertIn("a.action=e.action", sql)
        self.assertIn("a.target_type=e.target_type", sql)
        self.assertIn("a.target_id=e.target_id", sql)

    def test_malformed_upload_or_generic_conflict_is_not_authorization_evidence(self):
        for status, body in ((400, {"error": "InvalidMimeType"}), (422, {"error": "InvalidRequest"}),
                             (409, {"error": "Duplicate"}), (400, {"message": "Bad image bytes"})):
            self.assertFalse(m.authorization_denied(base.Response(status, json.dumps(body).encode())))
        for status, body in ((403, {}), (400, {"statusCode": "403"}),
                             (400, {"code": "42501"}), (400, {"message": "Media objects are immutable; upload a new unique path"})):
            self.assertTrue(m.authorization_denied(base.Response(status, json.dumps(body).encode())))


    def test_audit_failure_still_cleans_exact_auth_media_and_checks_inventory(self):
        calls = []
        class Db:
            def cleanup_context(self, *args):
                calls.append("context")
            def audit_receipts(self, *args):
                raise base.Failure("database_statement_failed")
            def final_inventory(self, *args):
                calls.append("inventory")
                return {}
        def child(label):
            return SimpleNamespace(state={"origin": base.ORIGIN, "run": self.run, "users": []},
                                   report={}, cleanup=lambda: (calls.append(label) or True))
        runner = object.__new__(m.Moderation)
        runner.db, runner.members, runner.moderator, runner.context, runner.report = Db(), child("members"), child("moderator"), {}, {}
        self.assertFalse(runner.cleanup())
        self.assertEqual(calls, ["context", "members", "moderator", "inventory"])
        self.assertEqual(runner.report["audit_verification_failure"], "database_statement_failed")


    def test_conflict_proves_nonretryable_pt409_body_and_http_status(self):
        self.assertTrue(m.business_conflict(base.Response(409, b'{"code":"PT409"}')))
        self.assertFalse(m.business_conflict(base.Response(409, b'{"code":"40001"}')))
        self.assertFalse(m.business_conflict(base.Response(409, b'{"code":"23505"}')))
        self.assertFalse(m.business_conflict(base.Response(500, b'{"code":"PT409"}')))


if __name__ == "__main__":
    unittest.main()
