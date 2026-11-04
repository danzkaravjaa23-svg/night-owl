#!/usr/bin/env python3
"""Opt-in real Auth/Storage acceptance on one disposable staging project only."""
from __future__ import annotations

import argparse
import base64
import hashlib
import http.client
import json
import os
from pathlib import Path
import re
import secrets
import ssl
import stat
import struct
import sys
import uuid
from urllib.parse import parse_qs, urlsplit
import zlib

REF = "sreojqqqhdzkfsrbvlpl"
ORIGIN = f"https://{REF}.supabase.co"
HOST = f"{REF}.supabase.co"
REPO = Path(__file__).resolve().parents[3]
VIDEO_SHA256 = "f9e0463f8212936c8dac808a3827a6ec7bb653c9172de8f45e8ac8cd60bc5b0f"
UUID = re.compile(r"[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\Z")
DENIED = {400, 401, 403, 404, 409, 422}
MAX_RESPONSE = 2 * 1024 * 1024


class Failure(Exception):
    """Only static, nonsecret codes may leave the runner."""
    def __init__(self, code, *, request_attempted=None):
        self.code = code if re.fullmatch(r"[a-z0-9_]{1,100}", code) else "invalid_failure_code"
        self.request_attempted = request_attempted
        super().__init__(self.code)


def require(condition, code):
    if not condition:
        raise Failure(code)


def unique_object(pairs):
    result = {}
    for key, value in pairs:
        require(key not in result, "duplicate_json_field")
        result[key] = value
    return result


def decode_json(raw):
    try:
        return json.loads(raw, object_pairs_hook=unique_object)
    except (ValueError, UnicodeError, TypeError):
        raise Failure("invalid_json") from None


def private_path(value, *, exists=True):
    path = Path(value).absolute()
    # Explicit /private/tmp paths avoid the /tmp symlink on macOS.
    require(not any(part.is_symlink() for part in [path, *path.parents]), "symlink_path")
    require(path == path.resolve(), "noncanonical_private_path")
    require(path != REPO and REPO not in path.parents, "private_path_inside_repository")
    require(not any((part / ".git").exists() or (part / ".git").is_symlink() for part in [path, *path.parents]),
            "private_path_inside_git_checkout")
    parent = path.parent.stat()
    require(parent.st_uid == os.getuid() and stat.S_IMODE(parent.st_mode) == 0o700,
            "private_parent_requires_0700")
    if exists:
        info = path.lstat()
        require(stat.S_ISREG(info.st_mode) and info.st_uid == os.getuid()
                and stat.S_IMODE(info.st_mode) == 0o600 and info.st_nlink == 1,
                "private_file_requires_0600")
    return path


def private_json(path):
    path = private_path(path)
    fd = os.open(path, os.O_RDONLY | os.O_NOFOLLOW)
    try:
        info = os.fstat(fd)
        require(stat.S_ISREG(info.st_mode) and stat.S_IMODE(info.st_mode) == 0o600
                and info.st_uid == os.getuid() and info.st_nlink == 1,
                "private_file_changed")
        require(info.st_size <= 131072, "private_file_too_large")
        with os.fdopen(fd, "rb", closefd=False) as stream:
            return decode_json(stream.read(131073))
    finally:
        os.close(fd)


def validate_key(key, role):
    require(isinstance(key, str) and re.fullmatch(r"[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+", key)
            and len(key) < 8192, "legacy_jwt_required")
    decoded = []
    for segment in key.split("."):
        try:
            raw = base64.b64decode(segment + "=" * (-len(segment) % 4), altchars=b"-_", validate=True)
        except ValueError:
            raise Failure("invalid_jwt_encoding") from None
        require(base64.urlsafe_b64encode(raw).decode().rstrip("=") == segment, "noncanonical_jwt")
        decoded.append(raw)
    header, claims = decode_json(decoded[0]), decode_json(decoded[1])
    require(isinstance(header, dict) and header.get("alg") == "HS256" and header.get("typ") == "JWT"
            and len(decoded[2]) == 32, "invalid_legacy_jwt_header")
    require(isinstance(claims, dict) and claims.get("role") == role and claims.get("ref") == REF,
            "wrong_key_role_or_project")


def load_config(path):
    config = private_json(path)
    require(isinstance(config, dict) and set(config) == {"origin", "anon_key", "service_role_key"},
            "invalid_config_fields")
    require(config["origin"] == ORIGIN, "nonallowlisted_origin")
    validate_key(config["anon_key"], "anon")
    validate_key(config["service_role_key"], "service_role")
    return config


def save_private(directory, name, data):
    target = directory / name
    temporary = directory / (".write-" + secrets.token_hex(12))
    fd = os.open(temporary, os.O_WRONLY | os.O_CREAT | os.O_EXCL | os.O_NOFOLLOW, 0o600)
    try:
        with os.fdopen(fd, "w", closefd=False) as stream:
            json.dump(data, stream, indent=2)
            stream.write("\n")
            stream.flush()
            os.fsync(fd)
        os.replace(temporary, target)
    finally:
        os.close(fd)
        temporary.unlink(missing_ok=True)


def image_fixture():
    def chunk(kind, data):
        return struct.pack(">I", len(data)) + kind + data + struct.pack(">I", zlib.crc32(kind + data))
    scanlines = (b"\0" + bytes([24, 80, 120]) * 16) * 16
    return (b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", struct.pack(">IIBBBBB", 16, 16, 8, 2, 0, 0, 0))
            + chunk(b"IDAT", zlib.compress(scanlines)) + chunk(b"IEND", b""))


def fixtures():
    video = Path(__file__).with_suffix(".mp4").read_bytes()
    require(hashlib.sha256(video).hexdigest() == VIDEO_SHA256, "video_fixture_changed")
    return [("posts", "photo.png", "image/png", "image", image_fixture()),
            ("stories", "video.mp4", "video/mp4", "video", video)]


class Response:
    def __init__(self, status, body=b""):
        self.status, self.body = status, body

    def json(self):
        return decode_json(self.body)


class Api:
    def __init__(self, config, *, execute=False, ca_file=None):
        require(execute and config.get("origin") == ORIGIN, "network_not_authorized")
        self.config, self.trace = config, []
        self.ca_file = os.fspath(ca_file) if ca_file is not None else None

    def request(self, stage, path, *, method="GET", token=None, service=False, data=None, binary=None,
                mime=None, headers=None):
        require(re.fullmatch(r"[a-z0-9_]{1,80}", stage), "invalid_stage")
        require(path.startswith(("/auth/v1/", "/storage/v1/", "/rest/v1/"))
                and not any(c in path for c in "\r\n\\#") and "://" not in path, "invalid_api_path")
        require(method in {"GET", "POST", "PUT", "PATCH", "DELETE"}, "invalid_method")
        require(not service or re.fullmatch(r"/auth/v1/admin/users(?:/[0-9a-f-]{36})?", path),
                "service_role_outside_synthetic_auth")
        key = self.config["service_role_key" if service else "anon_key"]
        request_headers = {"apikey": key, "Authorization": "Bearer " + (key if service else token or key)}
        if data is not None:
            body = json.dumps(data).encode()
            request_headers["Content-Type"] = "application/json"
        else:
            body = binary
            if binary is not None:
                request_headers["Content-Type"] = mime or "application/octet-stream"
        # These are internal test options, never inherited environment headers.
        require(not headers or set(headers) <= {"Prefer", "x-upsert", "Cache-Control"}, "invalid_header_override")
        request_headers.update(headers or {})
        connection, phase = None, "tls_context"
        def transport_failure(code):
            attempted = phase == "http_request"
            self.trace.append({"stage": stage, "status": None, "failure": code, "http_request_attempted": attempted})
            return Failure(code, request_attempted=attempted)
        try:
            # An explicit public CA bundle replaces default trust discovery.
            # Never fall back to an unverified context or disable host checks.
            context = ssl.create_default_context(cafile=self.ca_file)
            if context.verify_mode != ssl.CERT_REQUIRED or context.check_hostname is not True:
                raise transport_failure("tls_verification_required")
            phase = "connect"
            connection = http.client.HTTPSConnection(HOST, port=443, timeout=25, context=context)
            # Complete verified TLS before passing headers/body to HTTP. This
            # separates a definite unsent request from an unknown write outcome.
            connection.connect()
            phase = "http_request"
            connection.request(method, path, body=body, headers=request_headers)
            reply = connection.getresponse()
            require(not 300 <= reply.status < 400, "redirect_refused")
            raw = reply.read(MAX_RESPONSE + 1)
            require(len(raw) <= MAX_RESPONSE, "response_too_large")
            self.trace.append({"stage": stage, "status": reply.status})
            return Response(reply.status, raw)
        except ssl.SSLCertVerificationError:
            raise transport_failure("tls_verification_before_http" if phase != "http_request"
                                    else "tls_failure_request_outcome_unknown") from None
        except ssl.SSLError:
            raise transport_failure("tls_ca_load_failed" if phase == "tls_context" else
                                    "tls_handshake_before_http" if phase == "connect" else
                                    "tls_failure_request_outcome_unknown") from None
        except (OSError, http.client.HTTPException):
            raise transport_failure("tls_ca_load_failed" if phase == "tls_context" else
                                    "transport_connect_before_http" if phase == "connect" else
                                    "transport_failure_request_outcome_unknown") from None
        finally:
            if connection is not None:
                connection.close()


def signed_path(value, bucket, name):
    require(isinstance(value, str) and len(value) < 16384, "invalid_signed_url")
    if value.startswith("/object/"):
        value = "/storage/v1" + value
    parts = urlsplit(value)
    require((not parts.scheme and not parts.netloc or parts.scheme == "https" and parts.netloc == HOST)
            and not parts.fragment and parts.path == f"/storage/v1/object/sign/{bucket}/{name}",
            "foreign_signed_url")
    query = parse_qs(parts.query, keep_blank_values=True)
    require(set(query) == {"token"} and len(query["token"]) == 1 and query["token"][0], "invalid_signed_token")
    return parts.path + "?" + parts.query


def validate_journal(state):
    require(isinstance(state, dict) and state.get("origin") == ORIGIN
            and re.fullmatch(r"[0-9a-f]{32}", state.get("run", "")), "invalid_cleanup_journal")
    users = state.get("users")
    require(isinstance(users, list) and len(users) <= 2, "invalid_cleanup_users")
    labels, ids = set(), set()
    for user in users:
        label, uid = user.get("label"), user.get("id")
        require(label in {"a", "b"} and label not in labels, "invalid_cleanup_label")
        labels.add(label)
        require(user.get("email") == f"nightowl-staging-{state['run']}-{label}@example.test", "invalid_cleanup_email")
        require(re.fullmatch(r"[A-Za-z0-9_-]{43}", user.get("password", "")), "invalid_synthetic_password")
        require(uid is None or isinstance(uid, str) and UUID.fullmatch(uid) and uid not in ids, "invalid_cleanup_id")
        ids.add(uid)
        rows, objects = user.get("rows", []), user.get("objects", [])
        require(len(rows) <= 8 and len(objects) <= 16, "cleanup_inventory_too_large")
        for row in rows:
            require(row.get("table") in {"posts", "stories"} and UUID.fullmatch(row.get("id", "")), "invalid_cleanup_row")
        for obj in objects:
            require(uid and obj.get("bucket") in {"posts", "stories"}
                    and re.fullmatch(re.escape(f"{uid}/acceptance-{state['run']}/") + r"[a-z0-9_.-]+", obj.get("name", "")),
                    "invalid_cleanup_object")
    return state


class Runner:
    def __init__(self, api, directory, *, state=None, keep=False):
        self.api, self.directory, self.keep = api, directory, keep
        self.state = validate_journal(state) if state is not None else {"origin": ORIGIN, "run": uuid.uuid4().hex, "users": []}
        self.sessions = {}
        self.report = {"scope": "two_synthetic_users_pending_photo_video_api_acceptance", "project_ref": REF,
                       "production_accessed": False, "checks": [], "status": "running",
                       "limits": ["No device playback or UI acceptance", "No moderator approval, banned-account or erasure Edge acceptance",
                                  "No production-data or recovery parity claim"]}

    def journal(self):
        validate_journal(self.state)
        save_private(self.directory, "synthetic-state.json", self.state)

    def check(self, condition, code):
        require(condition, code)
        self.report["checks"].append(code)

    def request(self, stage, path, **kwargs):
        return self.api.request(stage, path, **kwargs)

    def make_user(self, label):
        user = {"label": label, "id": None, "email": f"nightowl-staging-{self.state['run']}-{label}@example.test",
                "password": secrets.token_urlsafe(32), "creation_uncertain": True, "rows": [], "objects": [], "cleaned": False}
        self.state["users"].append(user)
        self.journal()  # Record identity before the first external write.
        try:
            created = self.request("auth_create", "/auth/v1/admin/users", method="POST", service=True,
                                   data={"email": user["email"], "password": user["password"], "email_confirm": True,
                                         "user_metadata": {"username": f"synthetic-{self.state['run'][:16]}-{label}",
                                                           "nightowl_acceptance_run": self.state["run"]}})
        except Failure as error:
            if error.request_attempted is False:
                user["creation_uncertain"] = False
                self.journal()
            raise
        if 400 <= created.status < 500:
            user["creation_uncertain"] = False
            self.journal()
        require(created.status in {200, 201}, "auth_creation_failed")
        result = created.json()
        require(isinstance(result, dict) and UUID.fullmatch(result.get("id", "")), "invalid_created_user")
        user["id"], user["creation_uncertain"] = result["id"], False
        self.journal()
        wrong = self.request("wrong_password", "/auth/v1/token?grant_type=password", method="POST",
                             data={"email": user["email"], "password": secrets.token_urlsafe(32)})
        self.check(wrong.status in {400, 401, 422}, "wrong_password_rejected_" + label)
        login = self.request("password_login", "/auth/v1/token?grant_type=password", method="POST",
                             data={"email": user["email"], "password": user["password"]})
        require(login.status == 200, "password_login_failed")
        session = login.json()
        require(session.get("user", {}).get("id") == user["id"] and isinstance(session.get("access_token"), str)
                and session["access_token"], "session_identity_mismatch")
        # Do not assume HS256 for user sessions: hosted Auth may sign them
        # asymmetrically. Supabase validates the refreshed token at /user.
        require(isinstance(session.get("refresh_token"), str) and session["refresh_token"], "missing_refresh_token")
        refreshed = self.request("token_refresh", "/auth/v1/token?grant_type=refresh_token", method="POST",
                                 data={"refresh_token": session["refresh_token"]})
        require(refreshed.status == 200, "token_refresh_failed")
        session = refreshed.json()
        self.check(session.get("user", {}).get("id") == user["id"] and isinstance(session.get("access_token"), str)
                   and bool(session["access_token"]), "token_refresh_identity_" + label)
        self.sessions[label] = session["access_token"]
        verified = self.request("auth_user", "/auth/v1/user", token=self.sessions[label])
        self.check(verified.status == 200 and verified.json().get("id") == user["id"], "auth_session_verified_" + label)
        profile = self.request("profile_trigger", f"/rest/v1/profiles?id=eq.{user['id']}&select=id,moderation_status", token=self.sessions[label])
        self.check(profile.status == 200 and len(profile.json()) == 1 and profile.json()[0]["id"] == user["id"],
                   "auth_created_profile_" + label)
        active = self.request("social_active", "/rest/v1/rpc/social_active", method="POST", token=self.sessions[label], data={})
        self.check(active.status == 200 and active.json() is True, "active_member_" + label)
        return user

    def object(self, user, bucket, filename):
        obj = {"bucket": bucket, "name": f"{user['id']}/acceptance-{self.state['run']}/{filename}"}
        if obj not in user["objects"]:
            user["objects"].append(obj)
            self.journal()
        return obj

    def row(self, user, table):
        row = {"table": table, "id": str(uuid.uuid4())}
        user["rows"].append(row)
        self.journal()
        return row

    def unchanged(self, user, obj, data, stage):
        reply = self.request(stage, self.fresh_object_path(obj), token=self.sessions[user["label"]],
                             headers={"Cache-Control": "no-cache"})
        self.check(reply.status == 200 and len(reply.body) == len(data)
                   and hashlib.sha256(reply.body).digest() == hashlib.sha256(data).digest(), stage)

    @staticmethod
    def fresh_object_path(obj):
        # A different cache key per read prevents an earlier successful download
        # from hiding later byte changes or deletion. The nonce is not a secret.
        return f"/storage/v1/object/authenticated/{obj['bucket']}/{obj['name']}?nightowl_probe={uuid.uuid4().hex}"

    def cleanup_user(self, user):
        validate_journal(self.state)
        if user.get("cleaned"):
            return True
        if user["id"] is None:
            return not user.get("creation_uncertain")
        uid = user["id"]
        found = self.request("cleanup_identity", f"/auth/v1/admin/users/{uid}", service=True)
        if found.status == 404 and user.get("auth_delete_started"):
            user["cleaned"] = True
            self.journal()
            return True
        require(found.status == 200, "cleanup_identity_unavailable")
        identity = found.json()
        require(identity.get("id") == uid and identity.get("email") == user["email"]
                and identity.get("user_metadata", {}).get("nightowl_acceptance_run") == self.state["run"],
                "cleanup_identity_mismatch")
        # A resumed cleanup obtains its own fresh normal user session. The
        # service role never reads or mutates application rows or Storage.
        token = self.sessions.get(user["label"])
        if token is None:
            login = self.request("cleanup_login", "/auth/v1/token?grant_type=password", method="POST",
                                 data={"email": user["email"], "password": user["password"]})
            require(login.status == 200, "cleanup_login_failed")
            session = login.json()
            require(session.get("user", {}).get("id") == uid and isinstance(session.get("access_token"), str)
                    and session["access_token"], "cleanup_session_mismatch")
            token = self.sessions[user["label"]] = session["access_token"]
        for row in user["rows"]:
            path = f"/rest/v1/{row['table']}?id=eq.{row['id']}&user_id=eq.{uid}"
            deleted = self.request("cleanup_row", path, method="DELETE", token=token)
            require(deleted.status == 204, "cleanup_row_failed")
            read = self.request("cleanup_row_verify", path + "&select=id", token=token)
            require(read.status == 200 and read.json() == [], "cleanup_row_remains")
        for obj in user["objects"]:
            deleted = self.request("cleanup_object", f"/storage/v1/object/{obj['bucket']}", method="DELETE", token=token,
                                   data={"prefixes": [obj["name"]]})
            require(deleted.status == 200, "cleanup_object_failed")
            deleted_data = deleted.json()
            prefix, filename = obj["name"].rsplit("/", 1)
            listing = self.request("cleanup_object_metadata_verify", f"/storage/v1/object/list/{obj['bucket']}",
                                   method="POST", token=token, data={"prefix": prefix, "limit": 100, "offset": 0})
            require(listing.status == 200, "cleanup_object_metadata_request_failed")
            entries = listing.json()
            require(isinstance(entries, list) and len(entries) < 100
                    and all(isinstance(entry, dict) and isinstance(entry.get("name"), str) for entry in entries),
                    "cleanup_object_metadata_response_invalid")
            matches = sum(entry["name"] in {filename, obj["name"]} for entry in entries)
            read = self.request("cleanup_object_verify", self.fresh_object_path(obj), token=token,
                                headers={"Cache-Control": "no-cache"})
            self.report.setdefault("cleanup_observations", []).append({
                "account": user["label"], "bucket": obj["bucket"], "delete_status": deleted.status,
                "delete_count": len(deleted_data) if isinstance(deleted_data, list) else None,
                "metadata_status": listing.status, "metadata_match_count": matches, "verification_status": read.status,
            })
            require(matches == 0, "cleanup_object_metadata_still_present")
            # Both a fresh metadata absence and a fresh byte-read failure are
            # required. No success is inferred from the DELETE response alone.
            require(read.status != 200, "cleanup_object_still_readable")
            require(read.status in {400, 404}, "cleanup_object_verification_failed")
        user["auth_delete_started"] = True
        self.journal()
        deleted = self.request("cleanup_auth", f"/auth/v1/admin/users/{uid}", method="DELETE", service=True)
        require(deleted.status in {200, 204, 404}, "cleanup_auth_failed")
        read = self.request("cleanup_auth_verify", f"/auth/v1/admin/users/{uid}", service=True)
        require(read.status == 404, "cleanup_auth_remains")
        user["cleaned"] = True
        self.journal()
        return True

    def cleanup(self):
        outcomes = []
        for user in self.state["users"]:
            account = user.get("label") if user.get("label") in {"a", "b"} else "unknown"
            try:
                complete = self.cleanup_user(user)
                outcomes.append(complete)
                if not complete:
                    self.report.setdefault("cleanup_failures", []).append({"account": account, "code": "cleanup_creation_outcome_unknown"})
            except Failure as error:
                outcomes.append(False)
                self.report.setdefault("cleanup_failures", []).append({"account": account, "code": error.code})
            except Exception:
                outcomes.append(False)  # No raw HTTP/credential-bearing diagnostics.
                self.report.setdefault("cleanup_failures", []).append({"account": account, "code": "cleanup_unexpected_error"})
        return all(outcomes)

    def exercise(self):
        media = fixtures()  # Verify all local fixture bytes before any request.
        self.report["fixtures"] = [{"mime": m[2], "bytes": len(m[4]), "sha256": hashlib.sha256(m[4]).hexdigest()} for m in media]
        a, b = self.make_user("a"), self.make_user("b")
        for table in ("posts", "stories", "profiles"):
            reply = self.request("schema_preflight", f"/rest/v1/{table}?select=id,moderation_status&limit=0", token=self.sessions["a"])
            self.check(reply.status == 200 and reply.json() == [], "schema_ready_" + table)
        # Both namespaces must contain positively verified real objects before
        # any foreign-reference negative; absence must not explain a denial.
        for owner in (a, b):
            token = self.sessions[owner["label"]]
            for bucket, filename, mime, kind, data in media:
                obj = self.object(owner, bucket, filename)
                endpoint = f"/storage/v1/object/{bucket}/{obj['name']}"
                unauth = self.request("anonymous_upload", endpoint, method="POST", binary=data, mime=mime)
                self.check(unauth.status in DENIED, "anonymous_upload_denied_" + owner["label"] + "_" + bucket)
                uploaded = self.request("owner_upload", endpoint, method="POST", token=token, binary=data, mime=mime,
                                        headers={"x-upsert": "true"} if bucket == "stories" else None)
                self.check(uploaded.status in {200, 201}, "upload_" + owner["label"] + "_" + bucket)
                self.unchanged(owner, obj, data, "owner_download_" + owner["label"] + "_" + bucket)
        remembered = []
        for owner, other in ((a, b), (b, a)):
            token, foreign = self.sessions[owner["label"]], self.sessions[other["label"]]
            for bucket, filename, mime, kind, data in media:
                obj = self.object(owner, bucket, filename)
                endpoint = f"/storage/v1/object/{bucket}/{obj['name']}"
                row = self.row(owner, bucket)
                payload = {"id": row["id"], "user_id": owner["id"], "caption": "Synthetic staging acceptance",
                           "media_url": ORIGIN + f"/storage/v1/object/public/{bucket}/{obj['name']}", "media_type": kind}
                if bucket == "posts":
                    payload["media_urls"] = [payload["media_url"]]
                else:
                    payload["duration"] = 1
                created = self.request("publish_pending", f"/rest/v1/{bucket}", method="POST", token=token,
                                       data=payload, headers={"Prefer": "return=representation"})
                expected = {key: payload[key] for key in ("id", "user_id", "media_url", "media_type")}
                expected["moderation_status"] = "pending"
                if bucket == "posts":
                    expected["media_urls"] = payload["media_urls"]
                def matches_published(response):
                    rows = response.json()
                    return (isinstance(rows, list) and len(rows) == 1 and isinstance(rows[0], dict)
                            and all(rows[0].get(key) == value for key, value in expected.items()))
                self.check(created.status == 201 and matches_published(created),
                           "pending_publication_" + owner["label"] + "_" + bucket)
                owner_read = self.request("owner_publication_read",
                    f"/rest/v1/{bucket}?id=eq.{row['id']}&user_id=eq.{owner['id']}&select=" + ",".join(expected), token=token)
                self.check(owner_read.status == 200 and matches_published(owner_read),
                           "owner_publication_identity_" + owner["label"] + "_" + bucket)
                for viewer, viewer_token in (("other", foreign), ("anonymous", None)):
                    read = self.request("pending_visibility", f"/rest/v1/{bucket}?id=eq.{row['id']}&select=id", token=viewer_token)
                    self.check(read.status in {401, 403} or read.status == 200 and read.json() == [],
                               "pending_hidden_" + viewer + "_" + owner["label"] + "_" + bucket)
                    read = self.request("private_download", f"/storage/v1/object/authenticated/{bucket}/{obj['name']}", token=viewer_token)
                    self.check(read.status in DENIED, "download_denied_" + viewer + "_" + owner["label"] + "_" + bucket)
                    sign = self.request("private_sign", f"/storage/v1/object/sign/{bucket}/{obj['name']}", method="POST", token=viewer_token, data={"expiresIn": 60})
                    self.check(sign.status in DENIED, "sign_denied_" + viewer + "_" + owner["label"] + "_" + bucket)
                public = self.request("public_download", f"/storage/v1/object/public/{bucket}/{obj['name']}")
                self.check(public.status in DENIED, "public_url_private_" + owner["label"] + "_" + bucket)
                signed = self.request("owner_sign", f"/storage/v1/object/sign/{bucket}/{obj['name']}", method="POST", token=token, data={"expiresIn": 60})
                require(signed.status == 200, "owner_sign_failed")
                signed_body = signed.json()
                path = signed_path(signed_body.get("signedURL", signed_body.get("signedUrl")), bucket, obj["name"])
                fetched = self.request("signed_download", path, headers={"Cache-Control": "no-cache"})
                self.check(fetched.status == 200 and fetched.body == data, "signed_bytes_" + owner["label"] + "_" + bucket)
                for method, actor, extra in (("PUT", token, None), ("POST", token, {"x-upsert": "true"}), ("PUT", foreign, None)):
                    changed = self.request("overwrite_attempt", endpoint, method=method, token=actor,
                                           binary=data + b"changed", mime=mime, headers=extra)
                    require(changed.status in DENIED, "overwrite_accepted")
                deletion = self.request("referenced_delete", f"/storage/v1/object/{bucket}", method="DELETE", token=token, data={"prefixes": [obj["name"]]})
                require(deletion.status in DENIED, "referenced_delete_guard_not_exercised")
                spoof = self.request("moderation_spoof", f"/rest/v1/{bucket}?id=eq.{row['id']}", method="PATCH", token=token,
                                     data={"moderation_status": "approved"}, headers={"Prefer": "return=representation"})
                noop = spoof.status == 204 or spoof.status == 200 and spoof.json() == []
                require(spoof.status in DENIED or noop, "self_approval_unexpected_response")
                # UPDATE RLS may hide the row and return successful zero-row
                # semantics. Prove its exact identity/media/pending status
                # remains visible to the owner instead of trusting HTTP alone.
                after_spoof = self.request("moderation_spoof_verify",
                    f"/rest/v1/{bucket}?id=eq.{row['id']}&user_id=eq.{owner['id']}&select=" + ",".join(expected), token=token)
                self.check(after_spoof.status == 200 and matches_published(after_spoof),
                           "self_approval_blocked_" + owner["label"] + "_" + bucket)
                self.unchanged(owner, obj, data, "denied_mutations_preserve_bytes_" + owner["label"] + "_" + bucket)
                # Failed requests also have known synthetic identities for cleanup.
                denied_obj = self.object(other, bucket, "foreign-" + filename)
                foreign_upload = self.request("foreign_upload", f"/storage/v1/object/{bucket}/{denied_obj['name']}",
                                              method="POST", token=token, binary=data, mime=mime)
                require(foreign_upload.status in DENIED, "foreign_upload_accepted")
                invalid_row = self.row(owner, bucket)
                other_obj = self.object(other, bucket, filename)
                self.unchanged(other, other_obj, data, "foreign_fixture_exists_" + owner["label"] + "_" + bucket)
                spoof_payload = {**payload, "id": invalid_row["id"], "media_url": ORIGIN + f"/storage/v1/object/public/{bucket}/{other_obj['name']}"}
                if bucket == "posts":
                    spoof_payload["media_urls"] = [spoof_payload["media_url"]]
                bad = self.request("foreign_media_publication", f"/rest/v1/{bucket}", method="POST", token=token, data=spoof_payload)
                require(bad.status in DENIED, "foreign_media_reference_accepted")
                self.report["checks"].append("ownership_and_immutability_" + owner["label"] + "_" + bucket)
                remembered.append((owner, obj, data))
        if not self.keep:
            self.check(self.cleanup_user(a), "account_a_cleanup")
            alive = self.request("other_auth_preserved", "/auth/v1/user", token=self.sessions["b"])
            self.check(alive.status == 200 and alive.json().get("id") == b["id"], "other_auth_preserved")
        for user, obj, data in remembered:
            if user is b:
                self.unchanged(b, obj, data, "other_bytes_preserved_" + obj["bucket"])


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--execute", action="store_true", help="Allow writes only to the hard-pinned staging project")
    parser.add_argument("--config-file", help="0600 JSON in a 0700 directory outside Git")
    parser.add_argument("--ca-file", help="Optional existing public PEM CA bundle; certificate and hostname verification stay required")
    parser.add_argument("--workdir", help="New private run directory, or the existing directory for --cleanup-only")
    parser.add_argument("--keep-synthetic", action="store_true", help="Retain only this run's synthetic data for later inspection/cleanup")
    parser.add_argument("--cleanup-only", action="store_true", help="Remove only journaled synthetic identities after verifying their Auth marker")
    args = parser.parse_args(argv)
    if not args.execute:
        print(json.dumps({"status": "offline_plan", "project_ref": REF, "network": False, "private_files_read": False,
                          "requires": ["reviewed application baseline and target-specific 008/009 already installed",
                                       "private config JSON: origin, anon_key, service_role_key", "private work directory"],
                          "cleanup": "automatic unless --keep-synthetic; explicit --cleanup-only can resume"}))
        return 0
    runner = None
    report = {"status": "failed", "project_ref": REF, "production_accessed": False}
    try:
        require(args.config_file and args.workdir and not (args.keep_synthetic and args.cleanup_only), "invalid_execute_arguments")
        config = load_config(args.config_file)
        directory = private_path(args.workdir, exists=False)
        if args.cleanup_only:
            info = directory.lstat()
            require(stat.S_ISDIR(info.st_mode) and stat.S_IMODE(info.st_mode) == 0o700 and info.st_uid == os.getuid(), "invalid_workdir")
            state = private_json(directory / "synthetic-state.json")
        else:
            os.mkdir(directory, 0o700)  # No existing directory or archive can be overwritten.
            state = None
        runner = Runner(Api(config, execute=True, ca_file=args.ca_file), directory, state=state, keep=args.keep_synthetic)
        report = runner.report
        if args.cleanup_only:
            report["cleanup_complete"] = runner.cleanup()
            report["status"] = "cleanup_passed" if report["cleanup_complete"] else "cleanup_incomplete"
        else:
            runner.exercise()
            report["status"] = "passed"
    except Failure as error:
        report["status"], report["failure"] = "failed", error.code
    except Exception:
        report["status"], report["failure"] = "failed", "unexpected_runner_failure"
    finally:
        if runner:
            if not args.cleanup_only:
                report["cleanup_complete"] = False if args.keep_synthetic else runner.cleanup()
                report["synthetic_data_retained_by_request"] = args.keep_synthetic
                if not args.keep_synthetic and not report["cleanup_complete"]:
                    report["status"] = "failed"
                    report["cleanup_requires_private_journal_review"] = True
            report["http_trace"] = runner.api.trace
            report["passed_count"] = len(report["checks"])
            try:
                save_private(runner.directory, "cleanup-result.json" if args.cleanup_only else "acceptance-result.json", report)
            except Exception:
                report["status"], report["failure"] = "failed", "private_report_write_failed"
        print(json.dumps(report, sort_keys=True))
    return 0 if report["status"] in {"passed", "cleanup_passed"} else 1


if __name__ == "__main__":
    sys.exit(main())
