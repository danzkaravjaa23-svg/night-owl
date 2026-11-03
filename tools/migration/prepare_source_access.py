#!/usr/bin/env python3
"""Prepare source-only libpq files using a hidden, local terminal prompt.

Offline plan by default. Never connects, resets a password, or reads an existing
credential. Execution creates one new private directory outside every checkout.
"""
from __future__ import annotations

import argparse
import getpass
import ipaddress
import os
from pathlib import Path
import re
import stat
import sys
import warnings

import prepare_pgpass


class PreparationError(Exception):
    pass


def connection_fields(args):
    host = args.host
    if not host or any(character in host for character in "\r\n\0%"):
        raise PreparationError("Use one explicit hostname or IP address, without a URL or wildcard.")
    try:
        ipaddress.ip_address(host)
    except ValueError:
        if (len(host) > 253 or not all(re.fullmatch(r"[A-Za-z0-9](?:[A-Za-z0-9-]{0,61}[A-Za-z0-9])?", part)
                                      for part in host.split("."))):
            raise PreparationError("Use one explicit hostname or IP address, without a URL or wildcard.") from None
    if not 1 <= args.port <= 65535:
        raise PreparationError("Port must be between 1 and 65535.")
    for value in (args.database, args.user, args.service):
        if not re.fullmatch(r"[A-Za-z0-9_][A-Za-z0-9_.-]{0,127}", value):
            raise PreparationError("Database, user and service must be explicit simple names.")
    if args.sslrootcert == "system":
        ca = "system"
    else:
        candidate = Path(args.sslrootcert).expanduser()
        if not candidate.is_absolute() or any(c in str(candidate) for c in "\r\n\0"):
            raise PreparationError("CA must be system or an absolute certificate-file path.")
        # The CA is public configuration, not a credential; never read its bytes.
        ca_path = prepare_pgpass.no_symlinks(candidate)
        if not ca_path.is_file() or not os.access(ca_path, os.R_OK):
            raise PreparationError("The explicit CA certificate file must exist and be readable.")
        ca = str(ca_path)
    return host, str(args.port), args.database, args.user, args.service, ca


def open_directory(path):
    """Walk an absolute canonical directory path without following any links."""
    flags = os.O_RDONLY | os.O_DIRECTORY | os.O_NOFOLLOW
    current = os.open(path.anchor, flags)
    try:
        for part in path.parts[1:]:
            next_fd = os.open(part, flags, dir_fd=current)
            os.close(current)
            current = next_fd
        return current
    except BaseException:
        os.close(current)
        raise


def read_password():
    if not sys.stdin.isatty() or not sys.stderr.isatty():
        raise PreparationError("Run --execute yourself in a local terminal; redirected input is refused.")
    # getpass normally warns then falls back to echoed stdin. Turning that
    # warning into an exception prevents the fallback from ever reading input.
    with warnings.catch_warnings():
        warnings.simplefilter("error", getpass.GetPassWarning)
        password = getpass.getpass("Existing Database password (hidden; Enter to finish): ", stream=sys.stderr)
    if not password or any(character in password for character in "\r\n\0"):
        raise PreparationError("Password must be one non-empty line. Nothing was saved.")
    return password


def write_private(directory_fd, name, text, created):
    flags = os.O_WRONLY | os.O_CREAT | os.O_EXCL | os.O_NOFOLLOW
    fd = os.open(name, flags, 0o600, dir_fd=directory_fd)
    created.append(name)
    with os.fdopen(fd, "w", encoding="utf-8", newline="") as handle:
        os.fchmod(handle.fileno(), 0o600)
        handle.write(text)
        handle.flush()
        os.fsync(handle.fileno())


def prepare(args):
    host, port, database, user, service, ca = connection_fields(args)
    if ".." in Path(args.output).parts:
        raise PreparationError("Output must not contain parent-directory traversal.")
    output = prepare_pgpass.no_symlinks(args.output)
    if not Path(args.output).expanduser().is_absolute() or output.name in ("", ".", ".."):
        raise PreparationError("Output must be a new absolute directory outside Git.")
    parent_fd = open_directory(output.parent)
    directory_fd = None
    created_directory = False
    created_files = []
    password = None
    try:
        parent = os.fstat(parent_fd)
        if parent.st_uid != os.getuid() or parent.st_mode & 0o022:
            raise PreparationError("Output parent must belong to you and must not allow other users to write.")
        try:
            os.stat(output.name, dir_fd=parent_fd, follow_symlinks=False)
        except FileNotFoundError:
            pass
        else:
            raise PreparationError("Output already exists; choose a new directory. Nothing was overwritten.")
        password = read_password()
        os.mkdir(output.name, mode=0o700, dir_fd=parent_fd)
        created_directory = True
        directory_fd = os.open(output.name, os.O_RDONLY | os.O_DIRECTORY | os.O_NOFOLLOW, dir_fd=parent_fd)
        os.fchmod(directory_fd, 0o700)
        service_text = (f"[{service}]\nhost={host}\nport={port}\ndbname={database}\nuser={user}\n"
                        f"sslmode=verify-full\nsslrootcert={ca}\n")
        pass_text = ":".join(prepare_pgpass.escape(value) for value in (host, port, database, user, password)) + "\n"
        write_private(directory_fd, "service.conf", service_text, created_files)
        write_private(directory_fd, "pgpass", pass_text, created_files)
        os.fsync(directory_fd)
    except BaseException:
        # Remove only this attempt's newly created files. Existing output is
        # refused before prompting, and no existing credential is ever touched.
        if directory_fd is not None:
            for name in created_files:
                try:
                    os.unlink(name, dir_fd=directory_fd)
                except OSError:
                    pass
        if created_directory:
            try:
                os.rmdir(output.name, dir_fd=parent_fd)
            except OSError:
                pass
        raise
    finally:
        password = None
        if directory_fd is not None:
            os.close(directory_fd)
        os.close(parent_fd)
    print("Prepared new private service.conf and pgpass. No database connection or password reset was attempted.")


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--execute", action="store_true")
    parser.add_argument("--host", required=True)
    parser.add_argument("--port", required=True, type=int)
    parser.add_argument("--database", required=True)
    parser.add_argument("--user", required=True)
    parser.add_argument("--service", required=True)
    parser.add_argument("--sslrootcert", required=True, help="system (PostgreSQL 17+) or an absolute CA-file path")
    parser.add_argument("--output", required=True, help="New private directory outside Git; parent must already exist")
    args = parser.parse_args(argv)
    if not args.execute:
        print("Offline plan only: no prompt, files, credentials or network accessed. Add --execute in your local terminal to enter the existing password privately.")
        return 0
    try:
        prepare(args)
    except PreparationError as error:
        print(f"Preparation refused: {error}", file=sys.stderr)
        return 2
    except (KeyboardInterrupt, EOFError):
        print("Preparation cancelled. No connection or password reset was attempted.", file=sys.stderr)
        return 2
    except Exception:
        # Arbitrary getpass/I/O exceptions can contain input; never print them.
        print("Private preparation could not complete. No connection or password reset was attempted; no existing files were overwritten.", file=sys.stderr)
        return 2
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
