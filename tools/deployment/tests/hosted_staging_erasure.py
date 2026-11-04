#!/usr/bin/env python3
"""Opt-in email-account Edge erasure and receipt recovery on pinned staging only.

No deployment, configuration, role grants, service Storage requests or SQL
mutations. Two freshly created marker-bound accounts are the only subjects.
Completed journal entries are retained for the normal 30-day retention policy.
"""
from __future__ import annotations

import argparse
import hashlib
import http.client
import json
import os
from pathlib import Path
import re
import secrets
import ssl
import stat
import sys

import hosted_staging_acceptance as base
from hosted_staging_moderation import Database

require, Failure = base.require, base.Failure
EDGE_PATH = "/functions/v1/delete-account"
RECEIPT = re.compile(r"[A-Za-z0-9_-]{43}\Z")


class Edge:
    """A single fixed function; never accepts a URL, service key or redirect."""
    def __init__(self, api):
        require(api.config.get("origin") == base.ORIGIN, "nonallowlisted_edge_origin")
        self.api = api

    def request(self, stage, *, action=None, token=None, receipt=None):
        require(re.fullmatch(r"[a-z0-9_]{1,80}", stage), "invalid_edge_stage")
        require(action in {None, "prepare", "delete", "status"}, "invalid_edge_action")
        require(receipt is None or isinstance(receipt, str) and RECEIPT.fullmatch(receipt), "invalid_edge_receipt")
        require(action not in {"delete", "status"} or receipt is not None, "missing_edge_receipt")
        require(receipt is None or action in {"delete", "status"}, "unexpected_edge_receipt")
        headers = {"apikey": self.api.config["anon_key"], "Content-Type": "application/json"}
        if token is not None:
            require(isinstance(token, str) and token and "\r" not in token and "\n" not in token, "invalid_edge_token")
            headers["Authorization"] = "Bearer " + token
        body = None if action is None else {"action": action, "confirmation": "DELETE", "client_platform": "native"}
        if receipt is not None:
            body["receipt_token"] = receipt
        connection, attempted = None, False
        try:
            context = ssl.create_default_context(cafile=self.api.ca_file)
            require(context.verify_mode == ssl.CERT_REQUIRED and context.check_hostname is True, "tls_verification_required")
            connection = http.client.HTTPSConnection(base.HOST, port=443, timeout=55, context=context)
            connection.connect()  # Do not hand credentials to HTTP before verified TLS.
            attempted = True
            connection.request("GET" if body is None else "POST", EDGE_PATH,
                               body=None if body is None else json.dumps(body).encode(), headers=headers)
            response = connection.getresponse()
            require(not 300 <= response.status < 400, "edge_redirect_refused")
            raw = response.read(base.MAX_RESPONSE + 1)
            require(len(raw) <= base.MAX_RESPONSE, "edge_response_too_large")
            self.api.trace.append({"stage": stage, "status": response.status})
            return base.Response(response.status, raw)
        except (OSError, http.client.HTTPException):
            code = "edge_transport_outcome_unknown" if attempted else "edge_transport_before_http"
            self.api.trace.append({"stage": stage, "failure": code, "http_request_attempted": attempted})
            raise Failure(code, request_attempted=attempted) from None
        finally:
            if connection is not None:
                connection.close()


def validate_context(value, state):
    base.validate_journal(state)
    require(isinstance(value, dict) and set(value) == {"run", "owner_id", "prepare_started", "delete_started", "receipt"},
            "invalid_erasure_context")
    owner = next((u for u in state["users"] if u["label"] == "a"), None)
    require(value["run"] == state["run"] and (value["owner_id"] is None or owner is not None
            and value["owner_id"] == owner.get("id") and base.UUID.fullmatch(value["owner_id"])), "erasure_owner_mismatch")
    require(type(value["prepare_started"]) is bool and type(value["delete_started"]) is bool,
            "invalid_erasure_flags")
    require(value["receipt"] is None or isinstance(value["receipt"], str) and RECEIPT.fullmatch(value["receipt"]),
            "invalid_context_receipt")
    require(not value["prepare_started"] or value["owner_id"] is not None, "prepare_without_owner")
    require(value["receipt"] is None or value["prepare_started"], "receipt_without_prepare")
    require(not value["delete_started"] or value["receipt"] is not None, "delete_without_receipt")
    return value


class Erasure:
    def __init__(self, runner, database, *, context=None):
        self.runner, self.database, self.edge = runner, database, Edge(runner.api)
        self.context = validate_context(context, runner.state) if context is not None else {
            "run": runner.state["run"], "owner_id": None, "prepare_started": False,
            "delete_started": False, "receipt": None}
        self.report = {"project_ref": base.REF, "production_accessed": False, "checks": [], "status": "running",
                       "scope": "two_disposable_email_accounts_edge_erasure_and_receipt_recovery",
                       "limits": ["Admin-created email accounts do not prove public signup or email delivery",
                                  "No Apple revocation, device UI or full hosted recovery-parity claim",
                                  "No injected mid-erasure failure, concurrent workers or legacy/shared-content fixture",
                                  "Completed journal retained; no retention scheduler installed by this runner"]}

    def journal(self):
        validate_context(self.context, self.runner.state)
        base.save_private(self.runner.directory, "erasure-context.json", self.context)

    def check(self, condition, code):
        require(condition, code)
        self.report["checks"].append(code)

    def verify_identity(self, user):
        base.validate_journal(self.runner.state)
        require(user in self.runner.state["users"] and user.get("id"), "unknown_synthetic_user")
        reply = self.runner.request("edge_subject_identity", f"/auth/v1/admin/users/{user['id']}", service=True)
        require(reply.status == 200, "edge_subject_unavailable")
        found = reply.json()
        require(found.get("id") == user["id"] and found.get("email") == user["email"]
                and found.get("user_metadata", {}).get("nightowl_acceptance_run") == self.runner.state["run"],
                "edge_subject_identity_mismatch")

    def inventory(self, user):
        base.validate_journal(self.runner.state)
        require(user in self.runner.state["users"] and base.UUID.fullmatch(user.get("id", "")), "invalid_inventory_user")
        uid = user["id"]
        return self.database.query(f"""begin read only; select jsonb_build_object(
          'auth_users',(select count(*) from auth.users where id='{uid}'::uuid),
          'auth_identities',(select count(*) from auth.identities where user_id='{uid}'::uuid),
          'profiles',(select count(*) from public.profiles where id='{uid}'::uuid),
          'posts',(select count(*) from public.posts where user_id='{uid}'::uuid),
          'stories',(select count(*) from public.stories where user_id='{uid}'::uuid),
          'storage_objects',(select count(*) from storage.objects where split_part(name,'/',1)='{uid}' or owner_id='{uid}'));
          commit;""")

    def completed(self, user):
        """An HTTP success alone never proves deletion; verify exact receipt/checkpoints."""
        validate_context(self.context, self.runner.state)
        require(user.get("id") == self.context["owner_id"] and self.context["receipt"], "completion_owner_mismatch")
        digest = hashlib.sha256(self.context["receipt"].encode()).hexdigest()
        value = self.database.query(f"""begin read only; select jsonb_build_object(
          'count',count(*),'completed',coalesce(bool_and(state='completed'),false),
          'checkpoints',coalesce(bool_and(storage_cleared_at is not null and database_cleared_at is not null
            and completed_at is not null),false)) from account_private.erasure_jobs
          where user_id='{user['id']}'::uuid and receipt_hash='{digest}'; commit;""")
        require(value == {"count": 1, "completed": True, "checkpoints": True}, "erasure_completion_not_verified")
        inventory = self.inventory(user)
        require(set(inventory) == {"auth_users", "auth_identities", "profiles", "posts", "stories", "storage_objects"}
                and all(type(v) is int and v == 0 for v in inventory.values()), "erased_subject_inventory_remains")
        self.report["erased_owner_inventory"] = inventory
        self.report["retained_completed_journal"] = 1
        user["auth_delete_started"] = True
        self.runner.journal()

    def prepare(self, user):
        self.verify_identity(user)
        self.context.update(owner_id=user["id"], prepare_started=True)
        self.journal()  # Even a lost preparation response cannot trigger ordinary Auth cleanup.
        response = self.edge.request("edge_prepare", action="prepare", token=self.runner.sessions["a"])
        require(response.status == 200, "edge_prepare_failed")
        result = response.json()
        require(result.get("user_id") == user["id"] and result.get("apple_required") is False
                and RECEIPT.fullmatch(result.get("receipt_token", "")), "edge_prepare_identity_mismatch")
        self.context["receipt"] = result["receipt_token"]
        self.journal()
        self.check(True, "authenticated_prepare_returns_owner_bound_receipt")

    def delete(self, user):
        self.verify_identity(user)
        validate_context(self.context, self.runner.state)
        require(self.context["owner_id"] == user["id"] and self.context["receipt"], "delete_subject_mismatch")
        self.context["delete_started"] = True
        self.journal()
        response = self.edge.request("edge_delete", action="delete", receipt=self.context["receipt"], token=self.runner.sessions["a"])
        result = response.json()
        self.check(response.status == 200 and result.get("ok") is True and result.get("user_id") == user["id"],
                   "edge_delete_returns_strict_owner_receipt")
        self.completed(user)

    def recover_status(self, user):
        # A newly constructed transport has no Auth session. This models receipt
        # recovery after losing the client session; it does not inject a server crash.
        response = Edge(self.runner.api).request("edge_receipt_recovery", action="status", receipt=self.context["receipt"])
        result = response.json()
        require(response.status == 200 and result.get("ok") is True and result.get("user_id") == user["id"],
                "receipt_recovery_incomplete")
        self.completed(user)

    def upload(self, user, bucket, filename, mime, data):
        obj = self.runner.object(user, bucket, filename)
        response = self.runner.request("erasure_fixture_upload", f"/storage/v1/object/{bucket}/{obj['name']}",
            method="POST", token=self.runner.sessions[user["label"]], binary=data, mime=mime)
        self.check(response.status in {200, 201}, "upload_" + user["label"] + "_" + filename.replace('.', '_'))
        self.runner.unchanged(user, obj, data, "erasure_fixture_bytes_" + user["label"] + "_" + bucket)
        return obj

    def exercise(self):
        media = base.fixtures()
        self.database.preflight()
        response = self.edge.request("edge_method_guard")
        self.check(response.status == 405 and response.body == b"Method not allowed", "edge_function_method_guard")
        response = self.edge.request("edge_missing_auth", action="prepare")
        self.check(response.status == 401, "prepare_requires_auth")
        response = self.edge.request("edge_unknown_receipt", action="status", receipt=secrets.token_urlsafe(32))
        self.check(response.status == 404, "unknown_receipt_rejected")
        a, b = self.runner.make_user("a"), self.runner.make_user("b")
        remembered, erased_signed_paths = [], []
        for user in (a, b):
            for bucket, filename, mime, kind, data in media:
                obj = self.upload(user, bucket, filename, mime, data)
                row = self.runner.row(user, bucket)
                payload = {"id": row["id"], "user_id": user["id"], "caption": "Disposable erasure acceptance",
                           "media_url": base.ORIGIN + f"/storage/v1/object/public/{bucket}/{obj['name']}", "media_type": kind}
                if bucket == "posts":
                    payload["media_urls"] = [payload["media_url"]]
                else:
                    payload["duration"] = 1
                response = self.runner.request("erasure_fixture_row", f"/rest/v1/{bucket}", method="POST",
                    token=self.runner.sessions[user["label"]], data=payload)
                self.check(response.status == 201, "pending_row_" + user["label"] + "_" + bucket)
                if user is b:
                    remembered.append((obj, data))
                else:
                    signed = self.runner.request("erasure_signed_probe", f"/storage/v1/object/sign/{bucket}/{obj['name']}",
                        method="POST", token=self.runner.sessions["a"], data={"expiresIn": 600})
                    require(signed.status == 200, "erasure_sign_failed")
                    value = signed.json()
                    signed_path = base.signed_path(value.get("signedURL", value.get("signedUrl")), bucket, obj["name"])
                    before = self.runner.request("erasure_signed_positive", signed_path,
                                                 headers={"Cache-Control": "no-cache"})
                    self.check(before.status == 200 and before.body == data, "signed_positive_before_erasure_" + bucket)
                    erased_signed_paths.append((bucket, signed_path))
        self.prepare(a)
        response = self.edge.request("edge_receipt_without_auth", action="delete", receipt=self.context["receipt"])
        self.check(response.status == 401, "receipt_alone_cannot_delete")
        response = self.edge.request("edge_foreign_receipt", action="delete", receipt=self.context["receipt"], token=self.runner.sessions["b"])
        self.check(response.status == 404, "another_member_cannot_use_receipt")
        self.verify_identity(a)
        self.upload(a, "posts", "after-prepare.png", "image/png", base.image_fixture())
        self.check(True, "preparation_preserves_auth_and_allows_writes")
        self.delete(a)
        self.recover_status(a)
        self.check(True, "receipt_only_recovery_after_auth_deletion")
        self.recover_status(a)
        self.check(True, "receipt_status_is_repeatable_without_session")
        for bucket, path in erased_signed_paths:
            response = self.runner.request("erased_signed_bytes", path + "&nightowl_probe=" + secrets.token_hex(16),
                                           headers={"Cache-Control": "no-cache"})
            self.check(response.status in {400, 404} and response.json().get("error") in {"not_found", "Not found", "Object not found"},
                       "previously_valid_signed_bytes_absent_" + bucket)
        response = self.runner.request("deleted_auth_session", "/auth/v1/user", token=self.runner.sessions["a"])
        self.check(response.status in {401, 403, 404}, "deleted_auth_session_rejected")
        # Journal attempted rows/objects before writing, so any guard regression
        # is visible to the exact scoped inventory and subsequent cleanup.
        row = self.runner.row(a, "posts")
        response = self.runner.request("deleted_post_write", "/rest/v1/posts", method="POST", token=self.runner.sessions["a"],
                                       data={"id": row["id"], "user_id": a["id"], "caption": "Must be denied"})
        self.check(response.status in {401, 403} and response.json().get("code") in {"42501", "PGRST301", "PGRST303"},
                   "stale_jwt_cannot_write_post")
        obj = self.runner.object(a, "posts", "must-not-reappear.png")
        response = self.runner.request("deleted_storage_write", f"/storage/v1/object/posts/{obj['name']}", method="POST",
                                       token=self.runner.sessions["a"], binary=base.image_fixture(), mime="image/png")
        self.check(response.status in {400, 401, 403} and str(response.json().get("statusCode", response.status)) in {"401", "403"},
                   "stale_jwt_cannot_upload")
        self.completed(a)
        self.verify_identity(b)
        for obj, data in remembered:
            self.runner.unchanged(b, obj, data, "surviving_member_bytes_" + obj["bucket"])
        self.check(True, "other_member_auth_and_media_preserved")

    def cleanup(self, *, resume=False):
        results = []
        for user in self.runner.state["users"]:
            try:
                if user["label"] == "a" and self.context["prepare_started"]:
                    if self.context["receipt"]:
                        try:
                            self.recover_status(user)
                        except Failure:
                            if not resume:
                                raise  # Never automatically repeat an uncertain destructive call.
                            self.verify_identity(user)
                            self.restore_session(user)
                            self.delete(user)
                    else:
                        require(resume, "unknown_preparation_requires_explicit_resume")
                        self.restore_session(user)
                        self.prepare(user)
                        self.delete(user)
                results.append(self.runner.cleanup_user(user))
                inventory = self.inventory(user) if user.get("id") else {}
                require(all(type(v) is int and v == 0 for v in inventory.values()), "cleanup_inventory_not_empty")
                self.report.setdefault("cleanup_inventory", {})[user["label"]] = inventory
            except Failure as exc:
                results.append(False)
                self.report.setdefault("cleanup_failures", []).append({"account": user["label"], "code": exc.code})
            except Exception:
                results.append(False)
                self.report.setdefault("cleanup_failures", []).append({"account": user["label"], "code": "unexpected_cleanup_failure"})
        return all(results)

    def restore_session(self, user):
        self.verify_identity(user)
        response = self.runner.request("erasure_resume_login", "/auth/v1/token?grant_type=password", method="POST",
            data={"email": user["email"], "password": user["password"]})
        result = response.json()
        require(response.status == 200 and result.get("user", {}).get("id") == user["id"]
                and isinstance(result.get("access_token"), str) and result["access_token"], "resume_login_failed")
        self.runner.sessions["a"] = result["access_token"]


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--execute", action="store_true")
    parser.add_argument("--config-file")
    parser.add_argument("--service-file")
    parser.add_argument("--passfile")
    parser.add_argument("--psql")
    parser.add_argument("--ca-file")
    parser.add_argument("--workdir")
    parser.add_argument("--resume-cleanup", action="store_true", help="Explicitly resume only this journal's incomplete synthetic erasure")
    args = parser.parse_args(argv)
    if not args.execute:
        print(json.dumps({"status": "offline_plan", "project_ref": base.REF, "network": False, "private_files_read": False,
                          "requires": ["staging-only reviewed Edge deployment and enabled flag", "private exact-target credentials"],
                          "automatic_destructive_retry": False, "privilege_grants": False}))
        return 0
    erasure = None
    report = {"status": "failed", "project_ref": base.REF, "production_accessed": False}
    try:
        require(all((args.config_file, args.service_file, args.passfile, args.psql, args.workdir)), "missing_execute_arguments")
        config = base.load_config(args.config_file)
        db = Database(args.service_file, args.passfile, args.psql)
        db.preflight()
        directory = base.private_path(args.workdir, exists=False)
        if args.resume_cleanup:
            info = directory.lstat()
            require(stat.S_ISDIR(info.st_mode) and stat.S_IMODE(info.st_mode) == 0o700 and info.st_uid == os.getuid(), "invalid_workdir")
            state = base.private_json(directory / "synthetic-state.json")
            context = base.private_json(directory / "erasure-context.json")
        else:
            os.mkdir(directory, 0o700)
            state = context = None
        runner = base.Runner(base.Api(config, execute=True, ca_file=args.ca_file), directory, state=state)
        erasure = Erasure(runner, db, context=context)
        report = erasure.report
        erasure.journal()
        if not args.resume_cleanup:
            erasure.exercise()
        report["status"] = "cleanup_passed" if args.resume_cleanup else "passed"
    except Failure as exc:
        report["failure"] = exc.code
        report["status"] = "failed"
    except Exception:
        report["failure"] = "unexpected_erasure_runner_failure"
        report["status"] = "failed"
    finally:
        if erasure is not None:
            report["cleanup_complete"] = erasure.cleanup(resume=args.resume_cleanup)
            if not report["cleanup_complete"]:
                report["status"] = "failed"
            report["passed_count"] = len(report["checks"])
            report["setup_integrity_checks"] = len(erasure.runner.report["checks"])
            report["http_trace"] = erasure.runner.api.trace
            try:
                base.save_private(erasure.runner.directory, "erasure-result.json", report)
            except Exception:
                report["status"], report["failure"] = "failed", "private_result_write_failed"
        print(json.dumps(report, sort_keys=True))
    return 0 if report["status"] in {"passed", "cleanup_passed"} else 1


if __name__ == "__main__":
    sys.exit(main())
