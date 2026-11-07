#!/usr/bin/env python3
"""Prepare the approved native-only staging SIWA secrets; never deploy them.

Default execution is an offline plan and does not inspect private paths. Only
--execute reads the fixed approved key and writes a new private JSON object.
That object contains exactly the four Edge secret names/values, for private
handoff to Supabase's staging secrets UI. Never print or commit its contents.
No web OAuth secret, network access, process launch or environment export occurs.
"""
import argparse
import json
import os
from pathlib import Path
import re
import stat
import sys

sys.dont_write_bytecode = True
ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / 'tools/migration'))
import prepare_source_access

PROJECT = 'sreojqqqhdzkfsrbvlpl'
TEAM = 'DAVM2JZ4NN'
CLIENT_ID = 'com.nightowl.ub.nightOwlUb'
KEY_ID = '45KNSM48Z4'
PRIVATE_DIRECTORY = Path('/Users/usukhesbesty/Night Owl Apple Access 2026-11-04')
KEY_NAME = 'AuthKey_45KNSM48Z4.p8'
OUTPUT_NAME = 'night-owl-staging-native-apple-45KNSM48Z4.json'
FIELDS = ('APPLE_CLIENT_ID', 'APPLE_TEAM_ID', 'APPLE_KEY_ID', 'APPLE_PRIVATE_KEY')
MAX_KEY_BYTES = 8192


class PreparationError(Exception):
    """Only static diagnostic codes, never key/parser/path contents."""


def require(condition, code):
    if not condition:
        raise PreparationError(code)


def identity_check():
    require((PROJECT, TEAM, CLIENT_ID, KEY_ID, KEY_NAME, OUTPUT_NAME) == (
        'sreojqqqhdzkfsrbvlpl', 'DAVM2JZ4NN', 'com.nightowl.ub.nightOwlUb',
        '45KNSM48Z4', 'AuthKey_45KNSM48Z4.p8',
        'night-owl-staging-native-apple-45KNSM48Z4.json'), 'fixed_target_mismatch')


def private_directory():
    path = PRIVATE_DIRECTORY
    require(path.is_absolute() and '..' not in path.parts and
            not any(c in str(path) for c in '\r\n\0'), 'unsafe_private_directory')
    require(path != ROOT and ROOT not in path.parents, 'destination_inside_repository')
    # Inspect only known ancestors, never enumerate any checkout or private data.
    for ancestor in (path, *path.parents):
        require(not os.path.lexists(ancestor / '.git'), 'destination_inside_git')
    descriptor = prepare_source_access.open_directory(path)
    info = os.fstat(descriptor)
    if info.st_uid != os.getuid() or stat.S_IMODE(info.st_mode) != 0o700:
        os.close(descriptor)
        raise PreparationError('private_directory_requires_owner_mode_0700')
    return descriptor


def validate_private_key(raw):
    # Only unencrypted PKCS8 P-256, as required by the existing Edge handler.
    require(0 < len(raw) <= MAX_KEY_BYTES, 'invalid_private_key')
    require(re.fullmatch(rb'-----BEGIN PRIVATE KEY-----\r?\n'
                         rb'(?:[A-Za-z0-9+/=]+\r?\n)+'
                         rb'-----END PRIVATE KEY-----\r?\n?', raw) is not None,
            'invalid_private_key')
    try:
        from cryptography.hazmat.primitives import serialization
        from cryptography.hazmat.primitives.asymmetric import ec
        key = serialization.load_pem_private_key(raw, password=None)
        valid = isinstance(key, ec.EllipticCurvePrivateKey) and isinstance(key.curve, ec.SECP256R1)
    except ImportError:
        raise PreparationError('cryptography_dependency_missing') from None
    except Exception:
        raise PreparationError('invalid_private_key') from None
    require(valid, 'invalid_private_key')
    return raw.decode('ascii').replace('\r\n', '\n').strip() + '\n'


def read_private_key(directory_fd):
    fd = os.open(KEY_NAME, os.O_RDONLY | os.O_NOFOLLOW | os.O_NONBLOCK, dir_fd=directory_fd)
    with os.fdopen(fd, 'rb') as stream:
        info = os.fstat(stream.fileno())
        require(stat.S_ISREG(info.st_mode) and info.st_uid == os.getuid() and
                stat.S_IMODE(info.st_mode) == 0o600 and info.st_nlink == 1,
                'private_key_requires_owned_regular_mode_0600')
        require(0 < info.st_size <= MAX_KEY_BYTES, 'invalid_private_key')
        raw = stream.read(MAX_KEY_BYTES + 1)
        require(len(raw) == info.st_size, 'private_key_changed_during_read')
    return validate_private_key(raw)


def prepare():
    identity_check()
    directory_fd = private_directory()
    created = []
    try:
        try:
            os.stat(OUTPUT_NAME, dir_fd=directory_fd, follow_symlinks=False)
        except FileNotFoundError:
            pass
        else:
            raise PreparationError('destination_already_exists')
        private_key = read_private_key(directory_fd)
        values = dict(zip(FIELDS, (CLIENT_ID, TEAM, KEY_ID, private_key)))
        # The shared helper uses O_EXCL|O_NOFOLLOW, fchmod0600 and fsync.
        prepare_source_access.write_private(directory_fd, OUTPUT_NAME,
                                            json.dumps(values, indent=2) + '\n', created)
        os.fsync(directory_fd)
    except BaseException:
        for name in created:
            try:
                os.unlink(name, dir_fd=directory_fd)
            except OSError:
                pass
        raise
    finally:
        os.close(directory_fd)


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--execute', action='store_true', help='Read the fixed approved key; write one new private JSON file.')
    args = parser.parse_args(argv)
    try:
        identity_check()
        if args.execute:
            prepare()
        print(json.dumps({'status': 'prepared' if args.execute else 'offline_plan',
                          'project_ref': PROJECT, 'team_id': TEAM, 'client_id': CLIENT_ID,
                          'key_id': KEY_ID, 'fields': list(FIELDS),
                          'output_file_name': OUTPUT_NAME, 'file_mode': '0600',
                          'parent_mode': '0700', 'private_files_read': args.execute,
                          'network': False, 'deployed': False, 'web_oauth_secret': False}))
        return 0
    except PreparationError as exc:
        print(json.dumps({'status': 'failed', 'code': str(exc), 'deployed': False}))
        return 1
    except Exception:
        print(json.dumps({'status': 'failed', 'code': 'private_file_operation_failed', 'deployed': False}))
        return 1


if __name__ == '__main__':
    raise SystemExit(main())
