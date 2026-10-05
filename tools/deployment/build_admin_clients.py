#!/usr/bin/env python3
"""Produce configured client copies; never edit live/staged admin sources."""

from __future__ import annotations

import argparse
import base64
from dataclasses import dataclass
import hashlib
import json
import os
from pathlib import Path
import re
import shutil
import tempfile
import time
from urllib.parse import urlsplit, urlunsplit


ROOT = Path(__file__).resolve().parents[2]
CONFIG_KEYS = {"BACKEND_MODE", "BACKEND_URL", "BACKEND_PUBLIC_KEY"}
GENERATOR_ID = "nightowl-admin-clients-v1"
RUNTIME_FILES = (
    "web/admin/index.html",
    "chrome-extension/lib/supabase-client.js",
    "chrome-extension/background/service_worker.js",
)


class BuildError(ValueError):
    pass


def runtime_files(root: Path) -> tuple[str, ...]:
    # The user's staged directory move may not be part of the published tree.
    # Support both layouts without mutating or implicitly including that move.
    for relative in (RUNTIME_FILES[0], "admin-web/index.html"):
        if (root / relative).is_file():
            return (relative, *RUNTIME_FILES[1:])
    raise BuildError("Web admin source is missing from both supported layouts.")


def constant(text: str, name: str) -> str:
    matches = re.findall(r"\bconst\s+" + re.escape(name) + r"\s*=\s*(['\"])([^'\"\r\n]*)\1\s*;", text)
    if len(matches) != 1:
        raise BuildError(f"Expected exactly one {name} declaration in each client.")
    return matches[0][1]


def replace_constant(text: str, name: str, value: str) -> str:
    constant(text, name)  # Check the source contract before emitting anything.
    pattern = r"\bconst\s+" + re.escape(name) + r"\s*=\s*(['\"])([^'\"\r\n]*)\1\s*;"
    return re.sub(pattern, lambda _: f"const {name} = {json.dumps(value)};", text)


def source_defaults(root: Path) -> tuple[str, str]:
    values = []
    for relative in runtime_files(root):
        source = (root / relative).read_text()
        values.append((constant(source, "SUPABASE_URL"), constant(source, "SUPABASE_ANON")))
    if len(set(values)) != 1:
        raise BuildError("Source admin clients have different backend defaults; review them before building.")
    return values[0]


def anonymous_jwt(value: str, *, independent: bool) -> str:
    token = value.strip()
    if token.startswith("sb_secret_"):
        raise BuildError("Server secret keys must never be included in an admin client.")
    parts = token.split(".")
    if len(parts) != 3 or not all(parts):
        raise BuildError("A public anonymous JWT is required.")
    try:
        decoded = []
        for segment in parts[:2]:
            raw = base64.b64decode(segment + "=" * (-len(segment) % 4), altchars=b"-_", validate=True)
            decoded.append(json.loads(raw))
        header, claims = decoded
        signature = base64.b64decode(parts[2] + "=" * (-len(parts[2]) % 4), altchars=b"-_", validate=True)
        if not isinstance(header, dict) or not isinstance(claims, dict) or not signature:
            raise ValueError()
        if header.get("alg") not in ("HS256", "HS384", "HS512", "RS256", "ES256", "EdDSA"):
            raise ValueError()
        if claims.get("role") != "anon" or any(claims.get(field) not in (None, "") for field in ("sub", "email", "phone")):
            raise ValueError()
        if "exp" in claims and (not isinstance(claims["exp"], (int, float)) or claims["exp"] <= time.time()):
            raise ValueError()
        audience = claims.get("aud")
        if independent and not (audience == "authenticated" or isinstance(audience, list) and "authenticated" in audience):
            raise ValueError()
    except (ValueError, TypeError, UnicodeError):
        raise BuildError("Use a nonexpired public anonymous JWT, never a user or service-role token.") from None
    # Claims are inspected only to avoid shipping a secret/user credential.
    # No signature or issuer trust is verified here; PostgREST must do that.
    return token


def backend_origin(value: str, *, independent: bool, allow_local_http: bool) -> str:
    try:
        parsed = urlsplit(value.strip())
        host = parsed.hostname
        if not host or parsed.username or parsed.password or parsed.path not in ("", "/") or parsed.query or parsed.fragment:
            raise ValueError()
        if any(c.isspace() for c in value) or parsed.port == 0:
            raise ValueError()
        local = host in ("localhost", "127.0.0.1", "::1")
        if parsed.scheme != "https" and not (allow_local_http and local and parsed.scheme == "http"):
            raise ValueError()
        if independent and any(host == domain or host.endswith("." + domain) for domain in ("supabase.co", "supabase.in")):
            raise ValueError()
        return urlunsplit((parsed.scheme, parsed.netloc, "", "", ""))
    except (ValueError, TypeError):
        raise BuildError("Use an independent HTTPS API origin; local HTTP requires --allow-local-http.") from None


@dataclass(frozen=True)
class ClientConfig:
    mode: str
    url: str
    public_key: str

    @property
    def session_key(self):
        scope = hashlib.sha256(f"{self.mode}|{self.url}".encode()).hexdigest()[:16]
        return "nightowl_admin_session__" + scope

    def public_defines(self):
        return {"BACKEND_MODE": self.mode, "BACKEND_URL": self.url, "BACKEND_PUBLIC_KEY": self.public_key}

    @classmethod
    def parse(cls, values: dict, defaults: tuple[str, str], *, allow_local_http=False):
        if set(values) - CONFIG_KEYS:
            raise BuildError("Client configuration accepts only BACKEND_MODE, BACKEND_URL and BACKEND_PUBLIC_KEY.")
        if any(not isinstance(value, str) for value in values.values()):
            raise BuildError("Client configuration values must be text.")
        mode = values.get("BACKEND_MODE", "supabase").strip()
        if mode not in ("supabase", "postgres"):
            raise BuildError("BACKEND_MODE must be supabase or postgres.")
        url = values.get("BACKEND_URL", "").strip()
        key = values.get("BACKEND_PUBLIC_KEY", "").strip()
        if mode == "postgres" and (not url or not key):
            raise BuildError("PostgreSQL client builds require both an API origin and a public anonymous JWT.")
        if bool(url) != bool(key):
            raise BuildError("Configure the backend origin and public anonymous JWT together.")
        if not url:
            url, key = defaults
        return cls(
            mode,
            backend_origin(url, independent=mode == "postgres", allow_local_http=allow_local_http),
            anonymous_jwt(key, independent=mode == "postgres"),
        )


def render_runtime(source: str, config: ClientConfig, *, web_admin=False) -> str:
    text = replace_constant(source, "SUPABASE_URL", config.url)
    text = replace_constant(text, "SUPABASE_ANON", config.public_key)
    if web_admin:
        pattern = r"supabase\.createClient\(SUPABASE_URL,\s*SUPABASE_ANON\)"
        replacement = "supabase.createClient(SUPABASE_URL, SUPABASE_ANON, { auth: { storageKey: " + json.dumps(config.session_key) + " } })"
        text, count = re.subn(pattern, lambda _: replacement, text)
        if count != 1:
            raise BuildError("Web admin client initialization changed; review its storage-key configuration.")
    else:
        text = replace_constant(text, "SESSION_KEY", config.session_key)
    return text


def generated_manifest(source: str, config: ClientConfig) -> str:
    manifest = json.loads(source)
    if manifest.get("manifest_version") != 3:
        raise BuildError("Only the current Manifest V3 extension is supported.")
    manifest["host_permissions"] = [config.url + "/*"]
    manifest["content_security_policy"]["extension_pages"] = (
        "script-src 'self'; object-src 'none'; connect-src 'self' " + config.url
    )
    # Toolbar badges are part of chrome.action; 'badges' is not a permission.
    manifest["permissions"] = [permission for permission in manifest["permissions"] if permission != "badges"]
    if config.mode == "postgres":
        manifest["description"] = "Night Owl admin dashboard — independent backend"
    return json.dumps(manifest, ensure_ascii=False, indent=2) + "\n"


def allowed_output(root: Path, output: Path) -> Path:
    output = output.resolve()
    allowed_roots = ((root / "build").resolve(), Path(tempfile.gettempdir()).resolve())
    if not any(output.is_relative_to(allowed) and output != allowed for allowed in allowed_roots):
        raise BuildError("Output must be under ignored build/ or a temporary directory.")
    return output


def build(root: Path, output: Path, config: ClientConfig) -> dict:
    root, output = root.resolve(), allowed_output(root, output)
    runtime = runtime_files(root)
    previous = None
    if output.exists() and (not output.is_dir() or any(output.iterdir())):
        try:
            receipt = json.loads((output / "build-receipt.json").read_text())
            if receipt.get("generator") != GENERATOR_ID:
                raise ValueError()
        except (OSError, ValueError, TypeError):
            raise BuildError("Output contains unrelated files; choose a fresh output directory.") from None
    rendered = {
        relative: render_runtime((root / relative).read_text(), config, web_admin=relative == runtime[0])
        for relative in runtime
    }
    manifest = generated_manifest((root / "chrome-extension/manifest.json").read_text(), config)
    before = {relative: hashlib.sha256((root / relative).read_bytes()).hexdigest() for relative in (*runtime, "chrome-extension/manifest.json")}
    output.parent.mkdir(parents=True, exist_ok=True)
    stage = Path(tempfile.mkdtemp(prefix=".nightowl-clients-", dir=output.parent))
    try:
        ignore = shutil.ignore_patterns(".git", ".env", ".env.*", "__pycache__", "*.pyc")
        shutil.copytree((root / runtime[0]).parent, stage / "web-admin", ignore=ignore)
        shutil.copytree(root / "chrome-extension", stage / "chrome-extension", ignore=ignore)
        for relative, contents in rendered.items():
            destination = "web-admin/index.html" if relative == runtime[0] else relative
            (stage / destination).write_text(contents)
        (stage / "chrome-extension/manifest.json").write_text(manifest)
        if config.mode == "postgres":
            for relative in ("chrome-extension/popup/popup.html", "chrome-extension/dashboard/dashboard.html"):
                target = stage / relative
                target.write_text(target.read_text().replace("Supabase холбоотой", "Night Owl backend холбоотой").replace("Supabase-р нэвтрэх", "Бүртгэлээр нэвтрэх"))
        description = (
            "Generated Night Owl admin client copies\n\n"
            f"Mode: {config.mode}\nAPI origin: {config.url}\n"
            "Contains a PUBLIC anonymous JWT only; server authorization still enforces administrator privileges.\n"
            "Reauthentication is required because sessions are scoped to this backend.\n"
            "Provider integration, restored RLS and privileged moderation must pass staging tests before release.\n"
            "The web admin retains its existing CDN JavaScript/CSS dependencies.\n"
        )
        (stage / "README.txt").write_text(description)
        (stage / "web-admin/README.md").write_text(description)
        (stage / "chrome-extension/INSTALL.md").write_text(
            description + "\nLoad this generated chrome-extension folder as an unpacked extension in Chrome developer mode; log in with a verified admin account.\n"
        )
        receipt = {"generator": GENERATOR_ID, "backend_mode": config.mode, "backend_origin": config.url, "session_storage_key": config.session_key, "source_sha256": before}
        (stage / "build-receipt.json").write_text(json.dumps(receipt, indent=2) + "\n")
        after = {relative: hashlib.sha256((root / relative).read_bytes()).hexdigest() for relative in before}
        if after != before:
            raise BuildError("Source clients changed during the build; discard this build and repeat after editing finishes.")
        if output.exists() and any(output.iterdir()):
            previous = Path(tempfile.mkdtemp(prefix=".nightowl-previous-", dir=output.parent))
            previous.rmdir()
            output.replace(previous)
        try:
            stage.replace(output)
        except OSError:
            if previous is not None:
                previous.replace(output)
                previous = None
            raise
        if previous is not None:
            shutil.rmtree(previous)
            previous = None
        return receipt
    finally:
        if stage.exists():
            shutil.rmtree(stage)


def write_defines(root: Path, target: Path, config: ClientConfig):
    target = allowed_output(root, target)
    target.parent.mkdir(parents=True, exist_ok=True)
    descriptor, temporary = tempfile.mkstemp(prefix=".nightowl-defines-", dir=target.parent)
    try:
        with os.fdopen(descriptor, "w") as stream:
            json.dump(config.public_defines(), stream, indent=2)
            stream.write("\n")
        Path(temporary).replace(target)
    finally:
        if Path(temporary).exists():
            Path(temporary).unlink()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--config", type=Path, help="JSON file containing only the three public BACKEND_* settings")
    parser.add_argument("--output", type=Path)
    parser.add_argument("--execute", action="store_true", help="Write configured client copies; otherwise validate only")
    parser.add_argument("--defines-output", type=Path, help="Write the same three public settings for Flutter --dart-define-from-file")
    parser.add_argument("--allow-local-http", action="store_true", help="Allow only localhost/127.0.0.1/::1 for staging")
    args = parser.parse_args()
    try:
        values = json.loads(args.config.read_text()) if args.config else {key: os.environ[key] for key in CONFIG_KEYS if key in os.environ}
        if not isinstance(values, dict):
            raise BuildError("Client configuration must be a JSON object.")
        config = ClientConfig.parse(values, source_defaults(ROOT), allow_local_http=args.allow_local_http)
        output = args.output or ROOT / "build/deployment/admin-clients" / config.mode
        allowed_output(ROOT, output)
        if args.defines_output:
            allowed_output(ROOT, args.defines_output)
        if args.execute:
            build(ROOT, output, config)
            if args.defines_output:
                write_defines(ROOT, args.defines_output, config)
        print(json.dumps({"executed": args.execute, "output": str(output.resolve()), "backend_mode": config.mode, "backend_origin": config.url}))
    except (BuildError, OSError, json.JSONDecodeError) as error:
        parser.exit(2, f"Admin client build stopped: {error}\n")


if __name__ == "__main__":
    main()
