#!/usr/bin/env python3
"""Create a deterministic, allowlisted preparation ZIP from committed HEAD.

This is a handoff pack, not a Flutter checkout, signed app or deployment.
Only Python's standard library and read-only Git commands are used.
"""

import argparse
import base64
from datetime import datetime, timezone
import hashlib
import json
from pathlib import Path, PurePosixPath
import re
import subprocess
import sys
import tempfile
import zipfile


ROOT = Path(__file__).resolve().parents[2]
PACKAGE_NAME = "night-owl-app-store-prep-2026-11-03.zip"
EXACT_PATHS = frozenset({
    "docs/APP_STORE_SUBMISSION.md",
    "docs/APPLE_SIGN_IN_SETUP.md",
    "docs/RELEASE_READINESS.md",
    "docs/BUILD_VERIFICATION.json",
    "tools/deployment/build_ios.sh",
    "tools/deployment/ios_preflight.py",
    "tools/deployment/ios_native_inventory.py",
    "tools/deployment/ios_simulator_smoke.py",
    "tools/deployment/package_app_store_prep.py",
    "tools/deployment/STORE_BACKEND_ROLLOUT.md",
    "tools/deployment/store_backend_release.mjs",
    "tools/deployment/account_erasure_schedule.sql",
    "tools/deployment/tests/store_backend_metadata.sql",
    "tools/deployment/tests/store_platform_metadata.sql",
    "tools/deployment/tests/store_backend_preflight.sql",
    "tools/deployment/tests/admin_console_preflight.sql",
    "tools/deployment/tests/admin_console_postflight.sql",
    "tools/deployment/tests/interaction_boundaries_postflight.sql",
    "tools/deployment/tests/account_erasure_operations_status.sql",
    "tools/deployment/tests/account_erasure_prune.sql",
    "tools/deployment/tests/account_erasure_schedule_status.sql",
    "supabase/migrations/202611030008_account_erasure.sql",
    "supabase/migrations/202611030009_ugc_review.sql",
    "supabase/config.toml",
    "tools/deployment/tests/account_erasure_preflight.sql",
    "tools/deployment/tests/account_erasure_postflight.sql",
    "tools/deployment/tests/ugc_review_postflight.sql",
    ".github/workflows/ios-preparation.yml",
    ".github/workflows/backend-preparation.yml",
})
PREFIXES = ("docs/app-store/", "ios/", "legal/", "supabase/functions/delete-account/")
FLIGHT_PATTERN = re.compile(
    r"tools/deployment/tests/(?:account_erasure|ugc_review)_(?:pre|post)flight\.sql\Z"
)
FORBIDDEN_SUFFIXES = {
    ".p8", ".p12", ".pfx", ".pem", ".key", ".jks", ".keystore",
    ".mobileprovision", ".dump", ".backup", ".ipa", ".zip",
}
FORBIDDEN_PARTS = {"build", "output", "private", ".secrets", "xcuserdata", "DerivedData"}


def git(*args):
    return subprocess.check_output(["git", "-C", str(ROOT), *args])


def selected(path):
    return path in EXACT_PATHS or path.startswith(PREFIXES) or bool(FLIGHT_PATTERN.fullmatch(path))


def validate_source_path(path):
    parts = PurePosixPath(path).parts
    name = parts[-1] if parts else ""
    if (not parts or path.startswith("/") or ".." in parts or "\\" in path
            or set(parts) & FORBIDDEN_PARTS or name == ".env" or name.startswith(".env.")
            or name in {"key.properties", ".pgpass"}
            or PurePosixPath(path).suffix.lower() in FORBIDDEN_SUFFIXES):
        raise ValueError(f"Forbidden package source path: {path}")


def validate_payload(path, data):
    # Reject actual PEM key bodies and common non-public Supabase secret keys.
    # Source code which constructs an ephemeral test key is not a key body.
    pem_body = rb"-----BEGIN (?:[A-Z]+ )?PRIVATE KEY-----\r?\n(?:[A-Za-z0-9+/=]+\r?\n){2,}"
    if re.search(pem_body, data) or re.search(rb"\bsb_secret_[A-Za-z0-9_-]{20,}\b", data):
        raise ValueError(f"Credential-like material found; refuse packaging: {path}")
    for token in re.findall(rb"\beyJ[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+\b", data):
        try:
            payload = token.split(b".")[1]
            claims = json.loads(base64.urlsafe_b64decode(payload + b"=" * (-len(payload) % 4)))
        except (ValueError, UnicodeError):
            continue
        if isinstance(claims, dict) and claims.get("role") == "service_role":
            raise ValueError(f"Privileged JWT found; refuse packaging: {path}")


def read_snapshot(commit):
    files = {}
    for record in git("ls-tree", "-rz", "--full-tree", commit).split(b"\0"):
        if not record:
            continue
        metadata, raw_path = record.split(b"\t", 1)
        path = raw_path.decode("utf-8")
        if not selected(path):
            continue
        mode, kind, blob = metadata.decode("ascii").split()
        validate_source_path(path)
        if kind != "blob" or mode not in {"100644", "100755"}:
            raise ValueError(f"Only tracked regular files are allowed: {path}")
        data = git("cat-file", "blob", blob)
        validate_payload(path, data)
        files[path] = (data, int(mode, 8))
    missing = sorted(EXACT_PATHS - files.keys())
    if missing:
        raise ValueError("Required files are absent from HEAD; commit preparation first: "
                         + ", ".join(missing))
    for prefix in PREFIXES:
        if not any(path.startswith(prefix) for path in files):
            raise ValueError(f"Required tracked source tree is empty: {prefix}")
    return files


def preparation_readme(commit):
    return f"""# Night Owl UB — App Store preparation handoff

This is a partial source/documentation pack from Git commit {commit}.
It is NOT the full repository, a standalone Flutter checkout, a signed IPA,
an App Store upload, or evidence of production readiness. Use the full checkout
at that exact commit for dependency resolution, builds and referenced tests.

The pack contains only the explicit tracked allowlist: submission/privacy/legal
drafts, iOS project sources, unsigned-build helpers, iOS/backend CI definitions,
008/009 migration and erasure/reporting preparation. MANIFEST.json records the
SHA-256 and byte size of every payload file except the manifest itself.

Release gates remain: owner membership and signing Team/provisioning; final
signed archive/device and Apple login/revocation verification; reviewed backend
staging rollout and explicit service activation; moderation operations;
reviewer access/contact, screenshots and privacy/age/export declarations.
Read docs/APP_STORE_SUBMISSION.md and docs/RELEASE_READINESS.md for exact status.
An unsigned native build is not signing, deployment or App Store approval.

No production signing keys, credentials, environment files, private exports,
build products or local evidence directories are included. Public identifiers,
configuration references and generated synthetic-test code are source material,
not a configured production service. Never add owner secrets to this package.

The ZIP snapshots committed HEAD blobs, ignoring unstaged/staged changes and
untracked files. Entries are sorted, uncompressed, and use fixed UTC commit
timestamps/permissions for reproducibility. No network fetch is performed.
To refresh, commit the final evidence/source and run:
    python3 tools/deployment/package_app_store_prep.py

Native evidence is deliberately excluded; share a separately reviewed sanitized
CI artifact when required. No optional artifact directory is auto-discovered.
""".encode("utf-8")


def zip_info(path, timestamp, mode):
    info = zipfile.ZipInfo(path, date_time=timestamp)
    info.create_system = 3
    info.compress_type = zipfile.ZIP_STORED
    info.external_attr = mode << 16
    return info


def verify_archive(path, manifest):
    expected = {entry["path"]: entry for entry in manifest["files"]}
    with zipfile.ZipFile(path) as archive:
        names = archive.namelist()
        if len(names) != len(set(names)) or set(names) != set(expected) | {"MANIFEST.json"}:
            raise ValueError("ZIP payload differs from the allowlisted manifest")
        if archive.testzip() is not None:
            raise ValueError("ZIP CRC verification failed")
        if json.loads(archive.read("MANIFEST.json")) != manifest:
            raise ValueError("ZIP manifest verification failed")
        for name, entry in expected.items():
            data = archive.read(name)
            if len(data) != entry["size_bytes"] or hashlib.sha256(data).hexdigest() != entry["sha256"]:
                raise ValueError(f"ZIP payload verification failed: {name}")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output", type=Path,
                        default=ROOT / "build/releases" / PACKAGE_NAME)
    args = parser.parse_args()
    output = args.output.resolve()
    release_dir = (ROOT / "build/releases").resolve()
    if not output.is_relative_to(release_dir) or output.suffix.lower() != ".zip":
        parser.error("Output must be a ZIP inside this checkout's build/releases directory")
    if Path(git("rev-parse", "--show-toplevel").decode().strip()).resolve() != ROOT:
        raise ValueError("Script must belong to the intended Git checkout")
    commit = git("rev-parse", "HEAD").decode().strip()
    committed_at = datetime.fromtimestamp(int(git("show", "-s", "--format=%ct", commit)), timezone.utc)
    files = read_snapshot(commit)
    files["PREPARATION_README.md"] = (preparation_readme(commit), 0o100644)
    manifest = {
        "schema_version": 1,
        "scope": "App Store preparation handoff; partial committed source, unsigned, not a release",
        "head_commit": commit,
        "head_commit_utc": committed_at.isoformat().replace("+00:00", "Z"),
        "snapshot": "committed HEAD blobs only; no worktree or untracked content",
        "hash_algorithm": "SHA-256",
        "manifest_self_excluded": True,
        "native_evidence_included": False,
        "files": [{"path": name, "size_bytes": len(files[name][0]),
                   "sha256": hashlib.sha256(files[name][0]).hexdigest()}
                  for name in sorted(files)],
    }
    files["MANIFEST.json"] = ((json.dumps(manifest, indent=2, ensure_ascii=False) + "\n").encode("utf-8"), 0o100644)
    year = min(2107, max(1980, committed_at.year))
    timestamp = (year, committed_at.month, committed_at.day,
                 committed_at.hour, committed_at.minute, committed_at.second // 2 * 2)
    output.parent.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(prefix="nightowl-prep-", dir=output.parent) as temporary:
        candidate = Path(temporary) / "candidate.zip"
        with zipfile.ZipFile(candidate, "w", compression=zipfile.ZIP_STORED) as archive:
            for name in sorted(files):
                data, mode = files[name]
                archive.writestr(zip_info(name, timestamp, mode), data)
        verify_archive(candidate, manifest)
        candidate.replace(output)
    result = {"archive": str(output), "head_commit": commit,
              "payload_files": len(manifest["files"]), "size_bytes": output.stat().st_size,
              "sha256": hashlib.sha256(output.read_bytes()).hexdigest(),
              "verified": True}
    print(json.dumps(result, indent=2))


if __name__ == "__main__":
    try:
        main()
    except (ValueError, OSError, subprocess.CalledProcessError, zipfile.BadZipFile) as error:
        print(f"Preparation package failed: {error}", file=sys.stderr)
        sys.exit(1)
