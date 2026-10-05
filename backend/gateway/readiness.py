"""Fail-closed gate; no token issuance, JWT decoding, or application-row reads."""

from __future__ import annotations

import argparse
from concurrent.futures import ThreadPoolExecutor
import ipaddress
import json
import os
from pathlib import Path
import subprocess
import threading
import time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from urllib.error import HTTPError, URLError
from urllib.parse import urlsplit
from urllib.request import HTTPRedirectHandler, Request, build_opener


SERVICES = ("AUTH", "STORAGE", "REALTIME")
TIMEOUT = 2


def valid_origin(value: str) -> bool:
    """An operator-configured origin, never a client-supplied proxy target."""
    try:
        url = urlsplit(value)
        host = (url.hostname or "").lower()
        try:
            private = ipaddress.ip_address(host).is_private
        except ValueError:
            private = "." not in host or host.endswith(".internal")
        return bool(
            url.scheme in ("https", "http")
            and url.hostname
            and url.port != 0
            and not url.username
            and not url.password
            and url.path in ("", "/")
            and not url.query
            and not url.fragment
            and not any(c.isspace() for c in value)
            and ".supabase.co" not in url.hostname.lower()
            and not url.hostname.lower().endswith(".invalid")
            and not url.hostname.lower().endswith(".example")
            and url.hostname.lower() not in ("localhost", "127.0.0.1", "::1")
            and (url.scheme == "https" or private)
        )
    except (ValueError, TypeError):
        return False


def valid_health_path(value: str) -> bool:
    try:
        url = urlsplit(value)
        return bool(
            value.startswith("/") and not value.startswith("//")
            and not url.scheme and not url.netloc and not url.fragment
            and not url.query and not any(c.isspace() for c in value)
        )
    except (ValueError, TypeError):
        return False


def configuration_issues(env: dict[str, str]) -> list[str]:
    issues = []
    if not valid_origin(env.get("APP_WEB_ORIGIN", "")):
        issues.append("app_web_origin_unconfigured")
    for service in SERVICES:
        if not valid_origin(env.get(f"{service}_UPSTREAM", "")):
            issues.append(f"{service.lower()}_upstream_unconfigured")
        if not valid_health_path(env.get(f"{service}_READY_PATH", "")):
            issues.append(f"{service.lower()}_health_path_unconfigured")
    for flag in ("UPSTREAM_PROTOCOL_VERIFIED", "CUTOVER_APPROVED"):
        if env.get(flag, "").lower() != "true":
            issues.append(flag.lower() + "_required")
    return issues


def verification_key_configured(path: str) -> bool:
    """Check presence only; actual JWT signature verification is PostgREST's job."""
    try:
        content = Path(path).read_text().strip()
        if any(word in content.lower() for word in ("placeholder", "replace_me", "change_me")):
            return False
        if content.startswith("{"):
            key = json.loads(content)
            keys = key.get("keys", [key])
            return bool(keys) and all(
                isinstance(item, dict) and item.get("kty") in ("RSA", "EC", "OKP", "oct")
                for item in keys
            )
        return len(content) >= 32
    except (OSError, ValueError, TypeError):
        return False


class NoRedirect(HTTPRedirectHandler):
    def redirect_request(self, req, fp, code, msg, headers, newurl):
        return None


def http_ready(url: str) -> bool:
    try:
        # Redirects to a login screen are not proof of service readiness.
        with build_opener(NoRedirect).open(Request(url, method="GET"), timeout=TIMEOUT) as response:
            return response.status == 200
    except (HTTPError, URLError, TimeoutError, OSError, ValueError):
        return False


def database_inventory(env: dict[str, str]) -> dict:
    try:
        password = Path(env["READINESS_PASSWORD_FILE"]).read_text().strip()
        if not password:
            return {"ready": False, "error": "database_credentials_unconfigured"}
        child_env = {key: env[key] for key in ("PGHOST", "PGPORT", "PGUSER", "PGDATABASE")}
        child_env.update(PGPASSWORD=password, PGCONNECT_TIMEOUT="2", PATH=os.environ.get("PATH", ""))
        result = subprocess.run(
            ["psql", "--no-psqlrc", "--tuples-only", "--no-align", "--set=ON_ERROR_STOP=1",
             "--command=select nightowl_internal.readiness();"],
            env=child_env, capture_output=True, text=True, timeout=5, check=True,
        )
        report = json.loads(result.stdout)
        if not isinstance(report, dict) or report.get("ready") is not True:
            return {"ready": False, "inventory": report}
        return {"ready": True, "inventory": report}
    except (KeyError, OSError, ValueError, subprocess.SubprocessError):
        # Do not return credentials, connection strings, raw SQL errors or rows.
        return {"ready": False, "error": "database_inventory_unavailable"}


def evaluate_readiness(env: dict[str, str], *, probe=http_ready, inventory=database_inventory) -> dict:
    issues = configuration_issues(env)
    if not verification_key_configured(env.get("JWT_VERIFICATION_KEY_FILE", "")):
        issues.append("jwt_verification_key_unconfigured")
    if issues:
        return {"ready": False, "issues": issues}
    db = inventory(env)
    if db.get("ready") is not True:
        return {"ready": False, "issues": ["database_inventory_incomplete"]}
    targets = {
        "postgrest": env.get("POSTGREST_READY_URL", "http://postgrest:3001/ready"),
        **{name.lower(): env[f"{name}_UPSTREAM"].rstrip("/") + env[f"{name}_READY_PATH"] for name in SERVICES},
    }
    with ThreadPoolExecutor(max_workers=len(targets)) as executor:
        healthy = dict(zip(targets, executor.map(probe, targets.values())))
    unhealthy = [name + "_unavailable" for name, ready in healthy.items() if not ready]
    return {"ready": not unhealthy, "issues": unhealthy}


class ReadinessCache:
    def __init__(self, env: dict[str, str], evaluate=evaluate_readiness, ttl=3):
        self.env, self.evaluate, self.ttl = env, evaluate, ttl
        self._lock = threading.Lock()
        self._at = float("-inf")
        self._report = {"ready": False, "issues": ["readiness_not_checked"]}

    def get(self):
        with self._lock:
            now = time.monotonic()
            if now - self._at >= self.ttl:
                try:
                    self._report = self.evaluate(self.env)
                except Exception:
                    self._report = {"ready": False, "issues": ["readiness_check_failed"]}
                self._at = time.monotonic()
            return self._report.copy()


def route_response(path: str, cache: ReadinessCache) -> tuple[int, dict]:
    if path not in ("/healthz", "/readyz", "/gate"):
        return 404, {"ready": False, "issues": ["unknown_readiness_route"]}
    report = cache.get()
    return (200 if report.get("ready") is True else 503), report


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--check", action="store_true")
    args = parser.parse_args()
    if args.check:
        # Container check uses the running guard, not a second parallel SQL scan.
        raise SystemExit(0 if http_ready("http://127.0.0.1:8081/readyz") else 1)
    cache = ReadinessCache(dict(os.environ))

    class Handler(BaseHTTPRequestHandler):
        def do_GET(self):
            status, report = route_response(urlsplit(self.path).path, cache)
            body = json.dumps(report).encode()
            self.send_response(status)
            self.send_header("Content-Type", "application/json")
            self.send_header("Cache-Control", "no-store")
            self.send_header("Content-Length", str(len(body)))
            self.end_headers()
            self.wfile.write(body)

        def log_message(self, *_args):
            pass  # Never log query strings, bearer tokens or recovery links.

    ThreadingHTTPServer(("0.0.0.0", 8081), Handler).serve_forever()


if __name__ == "__main__":
    main()
