#!/usr/bin/env python3
"""Opt-in moderator/ban/selected-DM acceptance on the pinned disposable staging project.

Reuses the minimum runner's verified TLS, private journals, Auth/Storage setup
and exact-identity cleanup. No production target, schema or provider changes.
The database connection only bootstraps/revokes this run's synthetic moderator,
clears its ban for cleanup, and removes its exact synthetic DM/report fixtures.
Append-only moderation audit records are deliberately retained.
"""
from __future__ import annotations

import argparse
import configparser
import hashlib
import json
import os
from pathlib import Path
import re
import stat
import subprocess
import sys
import uuid

import hosted_staging_acceptance as base

require, Failure = base.require, base.Failure
SERVICE = "nightowl_staging"
POOLER = "aws-0-ap-northeast-1.pooler.supabase.com"


def identity_predicate(user, run):
    """Only values validated against the private synthetic journal enter SQL."""
    base.validate_journal({"origin": base.ORIGIN, "run": run, "users": [user]})
    require(user.get("id") is not None, "synthetic_identity_missing")
    return (f"id='{user['id']}'::uuid and email='{user['email']}' "
            f"and raw_user_meta_data->>'nightowl_acceptance_run'='{run}'")


class Database:
    def __init__(self, service_file, passfile, psql):
        self.service_file = base.private_path(service_file)
        self.passfile = base.private_path(passfile)
        config = configparser.ConfigParser(interpolation=None)
        config.read(self.service_file)
        require(SERVICE in config, "missing_staging_service")
        options = dict(config[SERVICE])
        expected = {"host": POOLER, "port": "5432", "dbname": "postgres",
                    "user": f"postgres.{base.REF}", "sslmode": "verify-full"}
        require(set(options) == set(expected) | {"sslrootcert"}
                and all(options.get(k) == v for k, v in expected.items()), "nonallowlisted_database")
        require(Path(options["sslrootcert"]).is_absolute()
                and Path(options["sslrootcert"]).is_file(), "database_ca_unavailable")
        self.psql = Path(psql)
        require(self.psql.is_absolute() and self.psql.is_file()
                and os.access(self.psql, os.X_OK), "psql_unavailable")

    def query(self, sql):
        env = {k: v for k, v in os.environ.items() if not k.startswith("PG")}
        env.update(PGSERVICEFILE=str(self.service_file), PGPASSFILE=str(self.passfile),
                   PGCONNECT_TIMEOUT="15", PGOPTIONS="-c statement_timeout=20000 -c lock_timeout=5000")
        try:
            result = subprocess.run([str(self.psql), "--no-psqlrc", "--no-password", "-qAt",
                                     "--set=ON_ERROR_STOP=1", f"--dbname=service={SERVICE}"],
                                    input=sql, text=True, capture_output=True, env=env, timeout=40)
        except (OSError, subprocess.TimeoutExpired):
            raise Failure("database_transport_failed") from None
        # Never emit raw diagnostics: they may include statement/identity context.
        require(result.returncode == 0, "database_statement_failed")
        require(len(result.stdout) < 65536, "database_response_too_large")
        return base.decode_json(result.stdout.strip())

    def preflight(self):
        value = self.query("begin read only; select jsonb_build_object('origin',storage_origin) "
                           "from admin_private.ugc_media_config where singleton; commit;")
        require(value == {"origin": base.ORIGIN}, "database_origin_mismatch")

    def flags(self, user, run, *, admin=None, banned=None):
        predicate = identity_predicate(user, run)
        require(admin is None or type(admin) is bool, "invalid_admin_flag")
        require(banned is None or type(banned) is bool, "invalid_banned_flag")
        setters = [f"{name}={'true' if value else 'false'}" for name, value in
                   (("is_admin", admin), ("is_banned", banned)) if value is not None]
        require(setters, "missing_flags")
        result = self.query(f"""begin;
        do $guard$ begin
          if not exists(select 1 from auth.users where {predicate}) then
            raise exception 'Synthetic identity mismatch';
          end if;
        end $guard$;
        with changed as(update public.profiles set {','.join(setters)}
          where id='{user['id']}'::uuid returning id,is_admin,is_banned)
        select jsonb_build_object('changed',(select count(*) from changed),
          'admin',(select is_admin from changed),'banned',(select is_banned from changed)); commit;""")
        require(result.get("changed") == 1 and (admin is None or result.get("admin") is admin)
                and (banned is None or result.get("banned") is banned), "synthetic_flags_not_changed")

    def cleanup_context(self, members, moderator, context):
        base.validate_journal(members.state)
        base.validate_journal(moderator.state)
        validate_context(context, members.state["run"], moderator.state["run"])
        known = [(u, r.state["run"]) for r in (members, moderator) for u in r.state["users"]
                 if u.get("id") and not u.get("cleaned")]
        if not known:
            return {"messages": 0, "reports": 0}
        guards = "\n".join(f"if not exists(select 1 from auth.users where {identity_predicate(u, run)}) "
                            "then raise exception 'Synthetic identity mismatch'; end if;" for u, run in known)
        ids = ",".join("'" + u["id"] + "'::uuid" for u, _ in known)
        message_ids = ",".join("'" + value + "'::uuid" for value in context["messages"]) or "null::uuid"
        # A report is generated server-side; exact target IDs + synthetic reporter
        # identity cover an unknown response without searching other reports.
        result = self.query(f"""begin;
        do $guard$ begin {guards} end $guard$;
        delete from public.reports where reporter_id in ({ids}) and target_type='message' and target_id in ({message_ids});
        delete from public.messages where sender_id in ({ids}) and receiver_id in ({ids}) and id in ({message_ids});
        select jsonb_build_object(
          'messages',(select count(*) from public.messages where id in ({message_ids})),
          'reports',(select count(*) from public.reports where reporter_id in ({ids}) and target_type='message' and target_id in ({message_ids})));
        commit;""")
        require(result == {"messages": 0, "reports": 0}, "synthetic_context_cleanup_incomplete")
        return result

    def final_inventory(self, members, moderator):
        for runner in (members, moderator):
            base.validate_journal(runner.state)
        ids = [u["id"] for runner in (members, moderator) for u in runner.state["users"] if u.get("id")]
        if not ids:
            return {}
        literals = ",".join("'" + uid + "'::uuid" for uid in ids)
        text_ids = ",".join("'" + uid + "'" for uid in ids)
        result = self.query(f"""begin read only;
        select jsonb_build_object(
          'auth_users',(select count(*) from auth.users where id in ({literals})),
          'auth_identities',(select count(*) from auth.identities where user_id in ({literals})),
          'profiles',(select count(*) from public.profiles where id in ({literals})),
          'posts',(select count(*) from public.posts where user_id in ({literals})),
          'stories',(select count(*) from public.stories where user_id in ({literals})),
          'storage_objects',(select count(*) from storage.objects where split_part(name,'/',1) in ({text_ids})),
          'messages',(select count(*) from public.messages where sender_id in ({literals}) or receiver_id in ({literals})),
          'reports',(select count(*) from public.reports where reporter_id in ({literals})));
        commit;""")
        require(isinstance(result, dict) and set(result) == {"auth_users", "auth_identities", "profiles", "posts", "stories",
                "storage_objects", "messages", "reports"} and all(type(v) is int and v == 0 for v in result.values()),
                "synthetic_final_inventory_not_empty")
        return result

    def audit_receipts(self, moderator, context):
        ids = [u["id"] for u in moderator.state["users"] if u.get("id")]
        if not ids:
            require(context["audits"] == [], "audit_actor_missing")
            return {"count": 0, "expected": 0, "matched": 0}
        require(len(ids) == 1 and base.UUID.fullmatch(ids[0]), "invalid_audit_actor")
        expected = context["audits"]
        # All fields are from the validated private receipt inventory. Return
        # aggregate proof, never account IDs, report bodies or audit row text.
        values = ",".join(f"('{a['id']}'::uuid,'{a['action']}','{a['target_type']}','{a['target_id']}')"
                          for a in expected) or "(null::uuid,null::text,null::text,null::text)"
        result = self.query(f"""begin read only;
        with expected(id,action,target_type,target_id) as(values {values})
        select jsonb_build_object(
          'count',(select count(*) from public.admin_audit_log where actor_id='{ids[0]}'::uuid),
          'expected',{len(expected)},
          'matched',(select count(*) from expected e join public.admin_audit_log a on a.id=e.id
            and a.actor_id='{ids[0]}'::uuid and a.action=e.action
            and a.target_type=e.target_type and a.target_id=e.target_id)); commit;""")
        require(type(result.get("count")) is int and result.get("expected") == len(expected)
                and result.get("matched") == len(expected), "audit_receipt_not_persisted")
        return result


def validate_context(context, member_run, moderator_run):
    require(isinstance(context, dict) and set(context) == {"member_run", "moderator_run", "messages", "audits"}
            and context["member_run"] == member_run and context["moderator_run"] == moderator_run,
            "invalid_moderation_context")
    messages = context["messages"]
    require(isinstance(messages, list) and len(messages) <= 8 and len(set(messages)) == len(messages)
            and all(isinstance(v, str) and base.UUID.fullmatch(v) for v in messages), "invalid_message_inventory")
    audits = context["audits"]
    require(isinstance(audits, list) and len(audits) <= 16, "invalid_audit_inventory")
    seen = set()
    for item in audits:
        require(isinstance(item, dict) and set(item) == {"id", "action", "target_type", "target_id"}
                and isinstance(item["id"], str) and base.UUID.fullmatch(item["id"]) and item["id"] not in seen
                and isinstance(item["target_id"], str) and base.UUID.fullmatch(item["target_id"])
                and item["action"] in {"approved_content", "rejected_content", "ban_user", "unban_user"}
                and item["target_type"] in {"profile", "post", "story", "user"}, "invalid_audit_inventory")
        seen.add(item["id"])


def authorization_denied(reply):
    if reply.status in {401, 403}:
        return True
    if reply.status not in {400, 422}:
        return False
    value = reply.json()
    if not isinstance(value, dict):
        return False
    return (value.get("statusCode") in {401, 403, "401", "403"}
            or value.get("code") in {"42501", "AccessDenied", "Unauthorized"}
            or value.get("error") in {"AccessDenied", "Unauthorized"}
            or value.get("message") in {
                "Media objects are immutable; upload a new unique path",
                "Referenced media cannot be replaced or removed; remove its content reference first",
                "new row violates row-level security policy"})


def business_conflict(reply):
    if reply.status != 409:
        return False
    value = reply.json()
    return isinstance(value, dict) and value.get("code") == "PT409"


class Moderation:
    def __init__(self, api, db, directory, *, resume=False):
        self.api, self.db, self.directory = api, db, directory
        self.members = self.runner("members", resume)
        self.moderator = self.runner("moderator", resume)
        self.context = (base.private_json(directory / "moderation-context.json") if resume else
                        {"member_run": self.members.state["run"],
                         "moderator_run": self.moderator.state["run"], "messages": [], "audits": []})
        validate_context(self.context, self.members.state["run"], self.moderator.state["run"])
        self.journal()
        self.report = {"scope": "synthetic_moderator_ban_selected_dm_api_acceptance", "project_ref": base.REF,
                       "production_accessed": False, "checks": [], "status": "running",
                       "limits": ["No public email delivery, Apple, device/UI or Edge erasure acceptance",
                                  "No production or recovery parity claim",
                                  "Append-only synthetic admin audit receipts intentionally retained"]}

    def runner(self, name, resume):
        path = self.directory / name
        if not resume:
            path.mkdir(mode=0o700)
        else:
            info = path.lstat()
            require(stat.S_ISDIR(info.st_mode) and stat.S_IMODE(info.st_mode) == 0o700
                    and info.st_uid == os.getuid() and not path.is_symlink(), "invalid_child_directory")
        state = base.private_json(path / "synthetic-state.json") if resume else None
        runner = base.Runner(self.api, path, state=state)
        runner.journal()
        return runner

    def journal(self):
        validate_context(self.context, self.members.state["run"], self.moderator.state["run"])
        base.save_private(self.directory, "moderation-context.json", self.context)

    def check(self, condition, code):
        require(condition, code)
        self.report["checks"].append(code)

    def rpc(self, name, data, token, stage=None):
        return self.api.request(stage or name, "/rest/v1/rpc/" + name, method="POST", token=token, data=data)

    def review(self, kind, target, version, decision, token):
        reply = self.rpc("admin_console_review", {"p_kind": kind, "p_target_id": target,
                         "p_version": version, "p_decision": decision,
                         "p_reason": "Synthetic staging moderation acceptance"}, token)
        require(reply.status == 200, "review_request_failed")
        value = reply.json()
        require(isinstance(value, dict) and value.get("target_id") == target and value.get("target_type") == kind
                and value.get("status") == decision and value.get("review_version") == version
                and isinstance(value.get("audit_id"), str) and base.UUID.fullmatch(value["audit_id"]),
                "invalid_review_receipt")
        self.record_audit(value["audit_id"], decision + "_content", kind, target)
        self.check(True, kind + "_" + decision + "_receipt")
        return value

    def action(self, action, target, token, report_id=None):
        reply = self.rpc("admin_console_action", {"p_action": action, "p_target_id": target,
                         "p_reason": "Synthetic staging moderation acceptance", "p_report_id": report_id}, token)
        require(reply.status == 200, "moderation_action_failed")
        value = reply.json()
        require(isinstance(value, dict) and value.get("target_id") == target and value.get("action") == action
                and value.get("target_type") == "user" and value.get("report_id") == report_id
                and value.get("report_status") == ("resolved" if report_id else None)
                and isinstance(value.get("audit_id"), str) and base.UUID.fullmatch(value["audit_id"]),
                "invalid_action_receipt")
        self.record_audit(value["audit_id"], action, "user", target)
        self.check(True, action + "_receipt")
        return value

    def record_audit(self, audit_id, action, kind, target):
        self.context["audits"].append({"id": audit_id, "action": action, "target_type": kind, "target_id": target})
        self.journal()

    def exact_row(self, table, uid, token):
        reply = self.api.request("exact_row_read", f"/rest/v1/{table}?id=eq.{uid}&select=id,moderation_status,moderation_version", token=token)
        require(reply.status == 200, "row_read_failed")
        rows = reply.json()
        require(isinstance(rows, list) and len(rows) == 1 and rows[0].get("id") == uid, "exact_row_missing")
        return rows[0]

    def visible(self, table, uid, token, expected, stage):
        reply = self.api.request(stage, f"/rest/v1/{table}?id=eq.{uid}&select=id", token=token)
        self.check(reply.status == 200 and reply.json() == ([{"id": uid}] if expected else []), stage)

    def message(self, sender, recipient, token, body):
        mid = str(uuid.uuid4())
        self.context["messages"].append(mid)
        self.journal()
        reply = self.api.request("create_dm", "/rest/v1/messages", method="POST", token=token,
                                 data={"id": mid, "sender_id": sender["id"], "receiver_id": recipient["id"], "body": body},
                                 headers={"Prefer": "return=representation"})
        require(reply.status == 201 and len(reply.json()) == 1 and reply.json()[0].get("id") == mid
                and reply.json()[0].get("body") == body, "synthetic_dm_create_failed")
        return mid

    def exercise(self):
        self.db.preflight()
        a, b = self.members.make_user("a"), self.members.make_user("b")
        m = self.moderator.make_user("a")
        owner, peer, admin = self.members.sessions["a"], self.members.sessions["b"], self.moderator.sessions["a"]
        self.db.flags(m, self.moderator.state["run"], admin=True)
        self.check(self.rpc("social_admin", {}, admin).json() is True, "synthetic_moderator_active")
        for token, name in ((owner, "member"), (None, "anonymous")):
            denied = self.rpc("admin_console_review_queue", {}, token)
            self.check(denied.status in base.DENIED, name + "_review_queue_denied")
        for user in (a, b):
            row = self.exact_row("profiles", user["id"], owner if user is a else peer)
            self.review("profile", user["id"], row["moderation_version"], "approved", admin)
        publications = []
        for bucket, filename, mime, kind, data in base.fixtures():
            obj = self.members.object(a, bucket, filename)
            uploaded = self.api.request("moderation_upload", f"/storage/v1/object/{bucket}/{obj['name']}",
                                        method="POST", token=owner, binary=data, mime=mime)
            self.check(uploaded.status in {200, 201}, bucket + "_upload")
            row = self.members.row(a, bucket)
            payload = {"id": row["id"], "user_id": a["id"], "caption": "Synthetic moderation fixture",
                       "media_url": base.ORIGIN + f"/storage/v1/object/public/{bucket}/{obj['name']}", "media_type": kind}
            if bucket == "posts":
                payload["media_urls"] = [payload["media_url"]]
            else:
                payload["duration"] = 1
            reply = self.api.request("create_pending", f"/rest/v1/{bucket}", method="POST", token=owner,
                                     data=payload, headers={"Prefer": "return=representation"})
            require(reply.status == 201 and len(reply.json()) == 1, "pending_create_failed")
            created = reply.json()[0]
            self.check(created.get("id") == row["id"] and created.get("moderation_status") == "pending", bucket + "_pending")
            self.visible(bucket, row["id"], peer, False, bucket + "_pending_hidden_peer")
            queue = self.rpc("admin_console_review_queue", {"p_kind": {"posts": "post", "stories": "story"}[bucket]}, admin)
            self.check(queue.status == 200 and any(item.get("id") == row["id"]
                       and item.get("review_version") == created["moderation_version"] for item in queue.json().get("items", [])),
                       bucket + "_queue_version_matches")
            self.review({"posts": "post", "stories": "story"}[bucket], row["id"], created["moderation_version"], "approved", admin)
            self.visible(bucket, row["id"], peer, True, bucket + "_approved_visible_peer")
            media = self.api.request("approved_media_read", base.Runner.fresh_object_path(obj), token=peer,
                                     headers={"Cache-Control": "no-cache"})
            self.check(media.status == 200 and hashlib.sha256(media.body).digest() == hashlib.sha256(data).digest(),
                       bucket + "_approved_media_integrity_peer")
            stale = self.rpc("admin_console_review", {"p_kind": {"posts": "post", "stories": "story"}[bucket], "p_target_id": row["id"],
                             "p_version": created["moderation_version"], "p_decision": "approved", "p_reason": "Synthetic stale review"}, admin)
            self.check(business_conflict(stale), bucket + "_repeat_approval_conflict")
            overwrite = self.api.request("approved_overwrite", f"/storage/v1/object/{bucket}/{obj['name']}",
                                         method="PUT", token=owner, binary=data, mime=mime)
            self.check(authorization_denied(overwrite), bucket + "_approved_overwrite_denied")
            self.members.unchanged(a, obj, data, bucket + "_bytes_immutable")
            publications.append((bucket, row, obj, created["moderation_version"]))
        # A moderator receives one participant-selected snapshot, never a DM browser.
        selected_body, sibling_body = "Selected synthetic report context", "Unreported synthetic private context"
        selected = self.message(a, b, owner, selected_body)
        sibling = self.message(a, b, owner, sibling_body)
        for mid in (selected, sibling):
            reply = self.api.request("moderator_dm_read", f"/rest/v1/messages?id=eq.{mid}&select=id,body", token=admin)
            self.check(reply.status == 200 and reply.json() == [], "moderator_direct_dm_read_denied")
        denied = self.rpc("report_ugc", {"p_target_type": "message", "p_target_id": sibling,
                          "p_reason": "spam", "p_details": None}, admin)
        self.check(denied.status in {401, 403}, "nonparticipant_report_denied")
        report = self.rpc("report_ugc", {"p_target_type": "message", "p_target_id": selected,
                          "p_reason": "harassment", "p_details": "Synthetic selected-message check"}, peer)
        require(report.status == 200 and isinstance(report.json(), str) and base.UUID.fullmatch(report.json()), "selected_report_failed")
        report_id = report.json()
        duplicate = self.rpc("report_ugc", {"p_target_type": "message", "p_target_id": selected,
                             "p_reason": "spam", "p_details": None}, peer)
        self.check(business_conflict(duplicate), "duplicate_report_conflict")
        denied = self.rpc("admin_console_reports", {}, peer)
        self.check(denied.status in {401, 403}, "member_report_console_denied")
        result = self.rpc("admin_console_reports", {}, admin)
        require(result.status == 200, "admin_report_read_failed")
        items = [item for item in result.json().get("items", []) if item.get("id") == report_id]
        self.check(len(items) == 1 and items[0].get("target_id") == selected
                   and items[0].get("target_author_id") == a["id"]
                   and items[0].get("target_excerpt") == selected_body and sibling_body not in json.dumps(result.json()),
                   "selected_context_only")
        self.action("ban_user", a["id"], admin, report_id)
        active = self.rpc("social_active", {}, owner)
        self.check(active.status == 200 and active.json() is False, "existing_session_ban_enforced")
        for bucket, row, obj, version in publications:
            self.visible(bucket, row["id"], peer, False, bucket + "_banned_author_hidden")
        blocked = self.members.object(a, "posts", "banned.png")
        reply = self.api.request("banned_upload", f"/storage/v1/object/posts/{blocked['name']}", method="POST", token=owner,
                                 binary=base.image_fixture(), mime="image/png")
        self.check(reply.status in {400, 401, 403}, "banned_upload_denied")
        blocked_mid = str(uuid.uuid4())
        self.context["messages"].append(blocked_mid)
        self.journal()
        reply = self.api.request("banned_send", "/rest/v1/messages", method="POST", token=owner,
                                 data={"id": blocked_mid, "sender_id": a["id"], "receiver_id": b["id"], "body": "Blocked synthetic message"})
        self.check(reply.status in {401, 403}, "banned_message_denied")
        denied = self.rpc("report_ugc", {"p_target_type": "message", "p_target_id": sibling,
                          "p_reason": "spam", "p_details": None}, owner)
        self.check(denied.status in {401, 403}, "banned_report_denied")
        self.action("unban_user", a["id"], admin)
        active = self.rpc("social_active", {}, owner)
        self.check(active.status == 200 and active.json() is True, "existing_session_unban_restored")
        for bucket, row, obj, version in publications:
            self.visible(bucket, row["id"], peer, True, bucket + "_unban_visibility_restored")
            self.review({"posts": "post", "stories": "story"}[bucket], row["id"], version, "rejected", admin)
            self.visible(bucket, row["id"], peer, False, bucket + "_rejected_hidden_peer")
            state = self.exact_row(bucket, row["id"], owner)
            self.check(state.get("moderation_status") == "rejected", bucket + "_rejected_owner_draft")
            denied = self.api.request("rejected_media_read", base.Runner.fresh_object_path(obj), token=peer,
                                      headers={"Cache-Control": "no-cache"})
            self.check(denied.status in base.DENIED, bucket + "_rejected_media_denied_peer")
        self.db.flags(m, self.moderator.state["run"], banned=True)
        denied = self.rpc("admin_console_review_queue", {}, admin)
        self.check(denied.status in {401, 403}, "banned_moderator_queue_denied")
        self.db.flags(m, self.moderator.state["run"], banned=False)
        self.check(self.rpc("admin_console_review_queue", {}, admin).status == 200, "moderator_access_restored")
        self.check(len(self.context["audits"]) == 8, "eight_distinct_moderation_receipts")
        audit = self.db.audit_receipts(self.moderator, self.context)
        self.check(audit["matched"] == 8 and audit["count"] == 8, "all_action_receipts_persisted")

    def reconcile_completed_auth(self):
        # A previous cleanup can lose the DELETE response after Auth committed.
        # The base runner sets auth_delete_started only after row/media absence
        # has been verified. Reconcile that exact ID before the SQL existence
        # guards, preserving the same marker checks for identities still present.
        for runner in (self.members, self.moderator):
            base.validate_journal(runner.state)
            for user in runner.state["users"]:
                if not user.get("id") or user.get("cleaned") or not user.get("auth_delete_started"):
                    continue
                reply = runner.request("cleanup_resume_identity", f"/auth/v1/admin/users/{user['id']}", service=True)
                if reply.status == 404:
                    user["cleaned"] = True
                    runner.journal()
                    continue
                require(reply.status == 200, "cleanup_resume_identity_unavailable")
                value = reply.json()
                require(value.get("id") == user["id"] and value.get("email") == user["email"]
                        and value.get("user_metadata", {}).get("nightowl_acceptance_run") == runner.state["run"],
                        "cleanup_resume_identity_mismatch")

    def cleanup(self):
        failures = []
        try:
            self.reconcile_completed_auth()
        except Failure as error:
            failures.append(error.code)
        # Commit revocation independently before any context deletion. A later
        # report/message failure cannot roll back the moderator's revocation.
        # Attempt every exact known identity even if another reconciliation or
        # revocation failed, so one broken account cannot retain another's flag.
        revocations = []
        for name, runner in (("moderator", self.moderator), ("members", self.members)):
            for user in runner.state["users"]:
                if user.get("id") and not user.get("cleaned"):
                    try:
                        self.db.flags(user, runner.state["run"], admin=False, banned=False)
                        revocations.append({"group": name, "account": user["label"], "confirmed": True})
                    except Failure as error:
                        failures.append(error.code)
                        revocations.append({"group": name, "account": user["label"], "confirmed": False})
        self.report["synthetic_privilege_revocations"] = revocations
        if failures:
            self.report["cleanup_failures"] = failures
            return False
        try:
            self.db.cleanup_context(self.members, self.moderator, self.context)
            self.report["synthetic_context_removed"] = True
        except Failure as error:
            self.report["cleanup_failure"] = error.code
            return False
        audit_ok = True
        try:
            audit = self.db.audit_receipts(self.moderator, self.context)
            self.report["append_only_audit_rows_retained"] = audit["count"]
            self.report["persisted_audit_receipts_verified"] = audit["matched"]
        except Failure as error:
            # Audit verification is an acceptance gate, but cannot prevent safe
            # exact fixture removal after privilege/context cleanup committed.
            self.report["audit_verification_failure"] = error.code
            audit_ok = False
        outcomes = [self.members.cleanup(), self.moderator.cleanup()]
        self.report["cleanup_failures"] = [entry for runner in (self.members, self.moderator)
                                           for entry in runner.report.get("cleanup_failures", [])]
        inventory_ok = True
        try:
            self.report["final_synthetic_inventory"] = self.db.final_inventory(self.members, self.moderator)
        except Failure as error:
            self.report["inventory_verification_failure"] = error.code
            inventory_ok = False
        return all(outcomes) and audit_ok and inventory_ok


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--execute", action="store_true")
    parser.add_argument("--config-file")
    parser.add_argument("--service-file")
    parser.add_argument("--passfile")
    parser.add_argument("--psql")
    parser.add_argument("--ca-file")
    parser.add_argument("--workdir")
    parser.add_argument("--cleanup-only", action="store_true")
    args = parser.parse_args(argv)
    if not args.execute:
        print(json.dumps({"status": "offline_plan", "project_ref": base.REF, "network": False,
                          "private_files_read": False, "synthetic_users": 3,
                          "operations": ["review approve/reject", "ban/unban", "selected-DM report privacy"],
                          "database": "exact synthetic moderator bootstrap/revoke and scoped context cleanup",
                          "retained": "append-only synthetic admin audit receipts"}))
        return 0
    runner = None
    report = {"status": "failed", "project_ref": base.REF, "production_accessed": False}
    try:
        require(all((args.config_file, args.service_file, args.passfile, args.psql, args.workdir)), "missing_execute_arguments")
        config = base.load_config(args.config_file)
        db = Database(args.service_file, args.passfile, args.psql)
        db.preflight()
        directory = base.private_path(args.workdir, exists=False)
        if args.cleanup_only:
            info = directory.lstat()
            require(stat.S_ISDIR(info.st_mode) and stat.S_IMODE(info.st_mode) == 0o700
                    and info.st_uid == os.getuid(), "invalid_workdir")
        else:
            directory.mkdir(mode=0o700)
        runner = Moderation(base.Api(config, execute=True, ca_file=args.ca_file), db, directory, resume=args.cleanup_only)
        report = runner.report
        if not args.cleanup_only:
            runner.exercise()
        report["status"] = "cleanup_passed" if args.cleanup_only else "passed"
    except Failure as error:
        report["failure"], report["status"] = error.code, "failed"
    except Exception:
        report["failure"], report["status"] = "unexpected_runner_failure", "failed"
    finally:
        if runner:
            try:
                report["cleanup_complete"] = runner.cleanup()
            except Exception:
                report["cleanup_complete"], report["cleanup_failure"] = False, "unexpected_cleanup_failure"
            if not report["cleanup_complete"]:
                report["status"] = "failed"
            report["http_trace"] = runner.api.trace
            report["passed_count"] = len(report["checks"])
            report["setup_checks"] = sum(len(r.report["checks"]) for r in (runner.members, runner.moderator))
            try:
                base.save_private(runner.directory, "cleanup-result.json" if args.cleanup_only else "moderation-result.json", report)
            except Exception:
                report["status"], report["failure"] = "failed", "private_report_write_failed"
        print(json.dumps(report, sort_keys=True))
    return 0 if report["status"] in {"passed", "cleanup_passed"} else 1


if __name__ == "__main__":
    sys.exit(main())
