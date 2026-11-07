"""Synthetic temporary key/file tests only; never open the approved Apple key."""
import contextlib
import importlib.util
import io
import json
import os
from pathlib import Path
import stat
import tempfile
import unittest
from unittest.mock import patch

from cryptography.hazmat.primitives import serialization
from cryptography.hazmat.primitives.asymmetric import ec

ROOT = Path(__file__).resolve().parents[3]
spec = importlib.util.spec_from_file_location('staging_apple_native', ROOT / 'tools/deployment/prepare_staging_apple_native.py')
helper = importlib.util.module_from_spec(spec)
spec.loader.exec_module(helper)


def synthetic_key(curve=None):
    return ec.generate_private_key(curve or ec.SECP256R1()).private_bytes(
        serialization.Encoding.PEM, serialization.PrivateFormat.PKCS8,
        serialization.NoEncryption())


class PreparationTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.directory = Path(self.temporary.name).resolve()
        self.directory.chmod(0o700)
        self.directory_patch = patch.object(helper, 'PRIVATE_DIRECTORY', self.directory)
        self.directory_patch.start()
        self.addCleanup(self.directory_patch.stop)
        self.key = self.directory / helper.KEY_NAME
        self.destination = self.directory / helper.OUTPUT_NAME
        self.raw = synthetic_key()
        self.key.write_bytes(self.raw)
        self.key.chmod(0o600)

    def run_command(self, args):
        output = io.StringIO()
        with contextlib.redirect_stdout(output), contextlib.redirect_stderr(output):
            code = helper.main(args)
        self.assertNotIn('BEGIN PRIVATE KEY', output.getvalue())
        self.assertNotIn(self.raw.decode().splitlines()[1], output.getvalue())
        return code, json.loads(output.getvalue())

    def test_default_plan_does_not_touch_private_paths(self):
        with patch.object(helper, 'prepare', side_effect=AssertionError('must not prepare')), \
                patch.object(helper, 'private_directory', side_effect=AssertionError('must not inspect')):
            code, result = self.run_command([])
        self.assertEqual(code, 0)
        self.assertFalse(result['private_files_read'])
        self.assertFalse(self.destination.exists())

    def test_execute_writes_exact_four_fields_mode_and_preserves_key(self):
        before = self.key.stat()
        code, result = self.run_command(['--execute'])
        self.assertEqual(code, 0)
        self.assertEqual(set(json.loads(self.destination.read_text())), set(helper.FIELDS))
        values = json.loads(self.destination.read_text())
        self.assertEqual(values, {'APPLE_CLIENT_ID': helper.CLIENT_ID, 'APPLE_TEAM_ID': helper.TEAM,
                                 'APPLE_KEY_ID': helper.KEY_ID, 'APPLE_PRIVATE_KEY': self.raw.decode()})
        self.assertEqual(stat.S_IMODE(self.destination.stat().st_mode), 0o600)
        self.assertEqual(self.key.read_bytes(), self.raw)
        self.assertEqual(self.key.stat().st_mtime_ns, before.st_mtime_ns)
        self.assertFalse(result['deployed'])
        self.assertFalse(result['network'])

    def test_refuse_overwrite_before_reading_key(self):
        self.destination.write_text('existing')
        with patch.object(helper, 'read_private_key', side_effect=AssertionError('must not read')):
            code, result = self.run_command(['--execute'])
        self.assertEqual(code, 1)
        self.assertEqual(result['code'], 'destination_already_exists')
        self.assertEqual(self.destination.read_text(), 'existing')

    def test_refuse_symlink_destination(self):
        self.destination.symlink_to(self.key)
        code, _ = self.run_command(['--execute'])
        self.assertEqual(code, 1)
        self.assertEqual(self.key.read_bytes(), self.raw)

    def test_invalid_pem_wrong_curve_encrypted_or_extra_material(self):
        encrypted = ec.generate_private_key(ec.SECP256R1()).private_bytes(
            serialization.Encoding.PEM, serialization.PrivateFormat.PKCS8,
            serialization.BestAvailableEncryption(b'DUMMY_ONLY'))
        for raw in [b'not a key', b'-----BEGIN PRIVATE KEY-----\nAAAA\n-----END PRIVATE KEY-----\n',
                    synthetic_key(ec.SECP384R1()), encrypted, self.raw * 2,
                    self.raw + b'UNEXPECTED', b'x' * 8193]:
            with self.subTest(size=len(raw)):
                self.key.write_bytes(raw)
                code, result = self.run_command(['--execute'])
                self.assertEqual(code, 1)
                self.assertEqual(result['code'], 'invalid_private_key')
                self.assertFalse(self.destination.exists())

    def test_bad_key_permissions(self):
        self.key.chmod(0o644)
        code, result = self.run_command(['--execute'])
        self.assertEqual(code, 1)
        self.assertEqual(result['code'], 'private_key_requires_owned_regular_mode_0600')
        self.assertFalse(self.destination.exists())

    def test_key_symlink_and_hardlink_rejected(self):
        alternate = self.directory / 'synthetic.p8'
        self.key.rename(alternate)
        self.key.symlink_to(alternate)
        self.assertEqual(self.run_command(['--execute'])[0], 1)
        self.key.unlink()
        os.link(alternate, self.key)
        self.assertEqual(self.run_command(['--execute'])[0], 1)
        self.assertFalse(self.destination.exists())

    def test_parent_requires_mode_0700(self):
        self.directory.chmod(0o755)
        code, result = self.run_command(['--execute'])
        self.assertEqual(code, 1)
        self.assertEqual(result['code'], 'private_directory_requires_owner_mode_0700')

    def test_git_destination_rejected(self):
        (self.directory / '.git').write_text('gitdir: dummy')
        code, result = self.run_command(['--execute'])
        self.assertEqual(code, 1)
        self.assertEqual(result['code'], 'destination_inside_git')
        self.assertFalse(self.destination.exists())

    def test_repository_destination_rejected_before_read(self):
        with patch.object(helper, 'PRIVATE_DIRECTORY', ROOT / 'build/private-unsafe'):
            code, result = self.run_command(['--execute'])
        self.assertEqual(code, 1)
        self.assertEqual(result['code'], 'destination_inside_repository')

    def test_parent_symlink_rejected(self):
        target = self.directory / 'real'
        target.mkdir(mode=0o700)
        link = self.directory / 'link'
        link.symlink_to(target, target_is_directory=True)
        with patch.object(helper, 'PRIVATE_DIRECTORY', link):
            self.assertEqual(self.run_command(['--execute'])[0], 1)
        self.assertFalse((target / helper.OUTPUT_NAME).exists())

    def test_fixed_identity_mismatch_fails_before_key_read(self):
        for field, wrong in [('PROJECT', 'production'), ('TEAM', 'OTHERTEAM0'),
                             ('CLIENT_ID', 'another.bundle'), ('KEY_ID', 'OTHERKEY00')]:
            with self.subTest(field=field), patch.object(helper, field, wrong), \
                    patch.object(helper, 'prepare', side_effect=AssertionError('must not prepare')):
                code, result = self.run_command(['--execute'])
                self.assertEqual(code, 1)
                self.assertEqual(result['code'], 'fixed_target_mismatch')

    def test_unexpected_exceptions_never_echo_secret(self):
        with patch.object(helper, 'prepare', side_effect=OSError(self.raw.decode())):
            code, result = self.run_command(['--execute'])
        self.assertEqual(code, 1)
        self.assertEqual(result['code'], 'private_file_operation_failed')

    def test_failed_write_removes_only_new_partial_file(self):
        def fail(directory_fd, name, text, created):
            helper.prepare_source_access.write_private_original(directory_fd, name, text, created)
            raise OSError('synthetic write failure')
        original = helper.prepare_source_access.write_private
        with patch.object(helper.prepare_source_access, 'write_private_original', original, create=True), \
                patch.object(helper.prepare_source_access, 'write_private', side_effect=fail):
            self.assertEqual(self.run_command(['--execute'])[0], 1)
        self.assertFalse(self.destination.exists())
        self.assertEqual(self.key.read_bytes(), self.raw)


if __name__ == '__main__':
    unittest.main()
