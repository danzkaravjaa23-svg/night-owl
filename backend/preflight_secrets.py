#!/usr/bin/env python3
"""Check private file mounts without printing secrets or starting the database."""

from __future__ import annotations

import argparse
import json
from pathlib import Path
import re
import shutil
import stat
import subprocess


ROOT = Path(__file__).resolve().parent
READERS = {
    "postgres": ("postgres_password", "authenticator_password", "readiness_password"),
    "postgrest": ("postgrest_db_uri", "jwt_verification_key"),
    "readiness": ("readiness_password", "jwt_verification_key"),
}


class PreflightError(ValueError):
    pass


def run(arguments: list[str], *, timeout=20) -> str:
    """Capture diagnostics privately; do not forward interpolated config/errors."""
    try:
        result = subprocess.run(arguments, capture_output=True, text=True, timeout=timeout, check=False)
    except (OSError, subprocess.TimeoutExpired):
        raise PreflightError("Docker command unavailable or timed out; secret readability is unverified.") from None
    if result.returncode:
        raise PreflightError("Docker command failed; secret readability is unverified. Inspect locally without exposing file contents.")
    return result.stdout.strip()


def private_files(configuration: dict) -> dict[str, Path]:
    files = {}
    for name in dict.fromkeys(secret for names in READERS.values() for secret in names):
        try:
            path = Path(configuration["secrets"][name]["file"])
            details = path.lstat()
            if not path.is_absolute() or not stat.S_ISREG(details.st_mode) or details.st_size == 0:
                raise ValueError()
            if stat.S_IMODE(details.st_mode) & 0o007:
                raise PreflightError(f"Secret {name} has permissions for other users; restrict ownership/ACLs without broadening access.")
            files[name] = path
        except (KeyError, TypeError, OSError, ValueError) as error:
            if isinstance(error, PreflightError):
                raise
            raise PreflightError(f"Secret {name} must be a nonempty private regular file at an absolute path.") from None
    return files


def numeric_user(value: str, service: str) -> str:
    # A UID alone can resolve a different default GID in a separate probe image.
    # Refuse it instead of claiming that a guessed group matches the reader.
    if not re.fullmatch(r"[0-9]+:[0-9]+", value):
        raise PreflightError(f"Reader {service} needs an explicitly verified numeric UID:GID; image user names or UID-only values are ambiguous.")
    return value


def image_details(image: str, runner=run) -> dict:
    try:
        details = json.loads(runner(["docker", "image", "inspect", image]))
        if len(details) != 1 or not re.fullmatch(r"sha256:[a-f0-9]{64}", details[0]["Id"]):
            raise ValueError()
        return details[0]
    except (ValueError, KeyError, TypeError):
        raise PreflightError("Required reviewed image is not loaded; pull/build it separately before preflight.") from None


def probe_base(user: str) -> list[str]:
    return [
        "docker", "run", "--rm", "--pull", "never", "--network", "none",
        "--read-only", "--cap-drop", "ALL", "--security-opt", "no-new-privileges:true",
        "--user", user, "--entrypoint", "/bin/sh",
    ]


def check(configuration: dict, runner=run) -> list[dict]:
    files = private_files(configuration)
    try:
        services = configuration["services"]
        probe = image_details(services["postgres"]["image"], runner)
        api = image_details(services["postgrest"]["image"], runner)
        postgres_identity = runner(probe_base("0:0") + [probe["Id"], "-c", "id -u postgres; id -g postgres"])
        fields = postgres_identity.splitlines()
        if len(fields) != 2:
            raise ValueError()
        users = {
            "postgres": numeric_user(":".join(fields), "postgres"),
            "readiness": numeric_user(services["readiness"]["user"], "readiness"),
            "postgrest": numeric_user(services["postgrest"].get("user") or api["Config"].get("User") or "0:0", "postgrest"),
        }
        if services["postgres"].get("user"):
            configured = numeric_user(services["postgres"]["user"], "postgres")
            # The official entrypoint drops root to postgres. A non-root user
            # override runs initialization as that explicitly configured UID.
            if configured.split(":", 1)[0] != "0":
                users["postgres"] = configured
    except (KeyError, ValueError, TypeError) as error:
        if isinstance(error, PreflightError):
            raise
        raise PreflightError("Compose reader identities could not be verified.") from None

    results = []
    for reader, names in READERS.items():
        mounts = []
        for name in names:
            # No shell interpolation; paths are individual Docker arguments.
            if any(character in str(files[name]) for character in (",", "\n", "\r")):
                raise PreflightError(f"Secret {name} path cannot be safely expressed as a Docker bind mount.")
            mounts += ["--mount", f"type=bind,source={files[name]},target=/run/secrets/{name},readonly"]
        # Open just one byte into /dev/null. File bytes and raw errors never leave
        # the probe. No database process, networking or write access is supplied.
        command = 'for name in "$@"; do dd if="/run/secrets/$name" of=/dev/null bs=1 count=1 status=none 2>/dev/null || exit 1; done'
        try:
            runner(probe_base(users[reader]) + mounts + [probe["Id"], "-c", command, "secret-check", *names])
        except PreflightError:
            raise PreflightError(f"Secret mounts are unreadable by {reader} ({users[reader]}); supply narrowly owned files/ACLs for this runtime identity.") from None
        results.append({"reader": reader, "uid_gid": users[reader], "secret_mounts_readable": True})
    return results


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--env-file", type=Path, default=ROOT / ".env")
    args = parser.parse_args()
    try:
        if not shutil.which("docker"):
            raise PreflightError("Docker is unavailable; container secret readability remains unverified.")
        output = run(["docker", "compose", "--project-directory", str(ROOT), "--env-file", str(args.env_file.resolve()), "-f", str(ROOT / "compose.yaml"), "config", "--format", "json"])
        configuration = json.loads(output)
        print(json.dumps({"verified": True, "readers": check(configuration)}))
        return 0
    except (PreflightError, ValueError, TypeError) as error:
        # Never print subprocess/config errors because Compose can contain secret
        # environment values even when this scaffold expects only file paths.
        message = str(error) if isinstance(error, PreflightError) else "Compose configuration is invalid; secret readability is unverified."
        print(json.dumps({"verified": False, "blocker": message}))
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
