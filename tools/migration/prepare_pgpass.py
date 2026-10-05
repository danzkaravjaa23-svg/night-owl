#!/usr/bin/env python3
"""Prepare a new private libpq passfile from private source/target files.

Plan only by default. This helper never connects to a database, prints a secret,
stores credentials in Git, follows user-created symlinks or overwrites a file.
"""
from __future__ import annotations

import argparse
import configparser
import os
from pathlib import Path
import stat
import sys

import migrate


def no_symlinks(path):
    lexical = Path(os.path.abspath(Path(path).expanduser()))
    # macOS system aliases are canonicalized; arbitrary user-created links are refused.
    for item in (lexical, *lexical.parents):
        if item.is_symlink() and item not in (Path("/tmp"), Path("/var")):
            raise migrate.MigrationError("Credential paths must not contain user-created symlinks.")
    return migrate.outside_repository(lexical)


def read_private(path, label):
    path = no_symlinks(path)
    flags = os.O_RDONLY | getattr(os, "O_NOFOLLOW", 0)
    try:
        fd = os.open(path, flags)
    except OSError:
        raise migrate.MigrationError(f"{label} must be an existing private regular file.") from None
    with os.fdopen(fd, "r", encoding="utf-8", newline="") as handle:
        metadata = os.fstat(handle.fileno())
        if not stat.S_ISREG(metadata.st_mode) or metadata.st_mode & 0o077:
            raise migrate.MigrationError(f"{label} must be a regular file with permissions 600 or stricter.")
        if hasattr(os, "getuid") and metadata.st_uid != os.getuid():
            raise migrate.MigrationError(f"{label} must belong to the current user.")
        return handle.read()


def parse_passfile(text):
    entries = []
    for line in text.splitlines():
        if not line or line.startswith("#"):
            continue
        fields, field, escaped = [], [], False
        for character in line:
            if escaped:
                field.append(character)
                escaped = False
            elif character == "\\":
                escaped = True
            elif character == ":":
                fields.append("".join(field))
                field = []
            else:
                field.append(character)
        if escaped:
            raise migrate.MigrationError("Target passfile has an incomplete escape.")
        fields.append("".join(field))
        if len(fields) != 5:
            raise migrate.MigrationError("Target passfile has an invalid entry.")
        entries.append(fields)
    return entries


def service(config, alias):
    migrate.service_name(alias)
    if not config.has_section(alias):
        raise migrate.MigrationError("Requested private service entry does not exist.")
    values = dict(config[alias])
    if any(key in values for key in ("password", "passfile", "service", "servicefile", "options")):
        raise migrate.MigrationError("Use explicit host/port/database/user service entries without embedded credentials/options.")
    required = ("host", "port", "dbname", "user")
    if any(not values.get(key) for key in required):
        raise migrate.MigrationError("Service entry requires explicit host, port, database and user.")
    if any(any(c in values[key] for c in ("\n", "\r", "\0")) or values[key] == "*" for key in required):
        raise migrate.MigrationError("Service connection fields must be explicit single-line values.")
    try:
        if not 1 <= int(values["port"]) <= 65535:
            raise ValueError
    except ValueError:
        raise migrate.MigrationError("Service port is invalid.") from None
    if values["host"] not in ("127.0.0.1", "::1", "localhost"):
        if values.get("sslmode") not in ("require", "verify-ca", "verify-full"):
            raise migrate.MigrationError("Remote source/target service must require TLS.")
    return [values[key] for key in required]


def password_line(password):
    # A text editor's single trailing LF/CRLF is allowed; all other whitespace is preserved.
    if password.endswith("\r\n"):
        password = password[:-2]
    elif password.endswith("\n"):
        password = password[:-1]
    if not password or any(c in password for c in ("\n", "\r", "\0")):
        raise migrate.MigrationError("Source password file must contain one non-empty password line.")
    return password


def escape(value):
    return value.replace("\\", "\\\\").replace(":", "\\:")


def prepare(args):
    config = configparser.ConfigParser(interpolation=None, strict=True)
    try:
        config.read_string(read_private(args.service_file, "Service file"))
    except configparser.Error:
        raise migrate.MigrationError("Private service file is invalid.") from None
    source = service(config, args.source_service)
    target = service(config, args.target_service)
    if source == target:
        raise migrate.MigrationError("Source and target connection identities must differ.")
    source_password = password_line(read_private(args.source_password_file, "Source password file"))
    entries = parse_passfile(read_private(args.target_passfile, "Target passfile"))
    matches = [entry for entry in entries if all(saved == "*" or saved == actual
               for saved, actual in zip(entry[:4], target))]
    if not matches or not matches[0][4]:
        raise migrate.MigrationError("Private target passfile has no matching non-empty target password.")
    target_password = matches[0][4]
    if any(c in target_password for c in ("\n", "\r", "\0")):
        raise migrate.MigrationError("Target password must be a single-line value.")
    output = no_symlinks(args.output)
    if not output.parent.is_dir() or output.parent.stat().st_mode & 0o077:
        raise migrate.MigrationError("Output parent must be an existing private directory with permissions 700.")
    text = "\n".join(":".join(escape(value) for value in fields)
                     for fields in (source + [source_password], target + [target_password])) + "\n"
    flags = os.O_WRONLY | os.O_CREAT | os.O_EXCL | getattr(os, "O_NOFOLLOW", 0)
    try:
        fd = os.open(output, flags, 0o600)
    except OSError:
        raise migrate.MigrationError("Output must be a new private file; existing files are never overwritten.") from None
    with os.fdopen(fd, "w", encoding="utf-8", newline="") as handle:
        handle.write(text)
        handle.flush()
        os.fsync(handle.fileno())
    print("New private passfile prepared. No credentials printed; no database connection attempted.")


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--execute", action="store_true")
    parser.add_argument("--service-file", default=os.environ.get("PGSERVICEFILE", ""))
    parser.add_argument("--source-service", default="nightowl_source")
    parser.add_argument("--target-service", default="nightowl_staging")
    parser.add_argument("--source-password-file", required=True)
    parser.add_argument("--target-passfile", required=True)
    parser.add_argument("--output", required=True)
    args = parser.parse_args(argv)
    if not args.execute:
        print("Offline credential-preparation plan only; no files read/written and no network attempted.")
        return 0
    try:
        prepare(args)
    except (migrate.MigrationError, OSError, UnicodeError) as error:
        # Do not stringify arbitrary file/parser errors; they could include credential text.
        message = str(error) if isinstance(error, migrate.MigrationError) else "Private credential preparation could not complete."
        print(f"Credential preparation refused: {message}", file=sys.stderr)
        return 2
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
