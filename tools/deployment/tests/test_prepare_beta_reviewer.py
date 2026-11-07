import contextlib
import importlib.util
import io
import json
from pathlib import Path
import stat
import tempfile
import unittest
from unittest.mock import patch

SPEC = importlib.util.spec_from_file_location('reviewer', Path(__file__).resolve().parents[3] / 'scripts/prepare_beta_reviewer.py')
reviewer = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(reviewer)


class FakeApi:
    def __init__(self, directory, state, admin=False, unknown_create=False):
        self.directory, self.state = directory, state
        self.admin, self.unknown_create = admin, unknown_create
        self.calls = []

    def request(self, stage, path, **kwargs):
        self.calls.append((path, kwargs))
        uid = '12345678-1234-1234-1234-123456789abc'
        if stage == 'reviewer_create':
            saved = json.loads((self.directory / reviewer.FILENAME).read_text())
            assert saved['phase'] == 'creating_account' and saved['password'] == self.state['password']
            if self.unknown_create:
                raise reviewer.base.Failure('transport_failure_request_outcome_unknown')
            value = {'id': uid, 'email': self.state['email'], 'role': 'authenticated',
                     'email_confirmed_at': '2026-11-06T00:00:00Z',
                     'user_metadata': {'nightowl_beta_review_marker': self.state['marker']}}
        elif stage == 'reviewer_login':
            value = {'user': {'id': uid}, 'access_token': 'SYNTHETIC-TOKEN-NOT-PERSISTED',
                     'refresh_token': 'SYNTHETIC-REFRESH-NOT-PERSISTED'}
        elif stage == 'reviewer_identity':
            value = {'id': uid}
        elif stage == 'reviewer_profile':
            value = [{'id': uid, 'is_admin': self.admin, 'is_banned': False}]
        elif stage == 'reviewer_admin_check':
            value = self.admin
        elif stage == 'reviewer_active_check':
            value = True
        else:
            raise AssertionError('Unexpected endpoint')
        return reviewer.base.Response(200, json.dumps(value).encode())


class ReviewerTests(unittest.TestCase):
    def test_default_opens_no_credentials_or_network(self):
        with patch.object(reviewer.base, 'load_config') as load, patch.object(reviewer.base, 'Api') as api, \
                patch.object(reviewer, 'new_private_directory') as mkdir, contextlib.redirect_stdout(io.StringIO()):
            self.assertEqual(reviewer.main([]), 0)
        load.assert_not_called(); api.assert_not_called(); mkdir.assert_not_called()

    def test_fixed_staging_and_strong_generated_identity(self):
        state = reviewer.new_identity()
        self.assertEqual(state['project_ref'], 'sreojqqqhdzkfsrbvlpl')
        self.assertEqual(state['origin'], 'https://sreojqqqhdzkfsrbvlpl.supabase.co')
        self.assertRegex(state['password'], r'^[A-Za-z0-9_-]{43}$')
        self.assertTrue(state['email'].endswith('@example.test'))
        body = reviewer.create_body(state)
        self.assertTrue(body['email_confirm'])
        self.assertNotIn('app_metadata', body)
        self.assertNotIn('role', body)
        username = body['user_metadata']['username']
        self.assertGreaterEqual(len(username), 3)
        self.assertLessEqual(len(username), 20)
        self.assertRegex(username, r'^[a-zA-Z0-9_.]+$')

    def test_private_permissions_no_overwrite_and_no_symlinks(self):
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp).resolve()
            directory = reviewer.new_private_directory(root / 'review')
            reviewer.base.save_private(directory, reviewer.FILENAME, reviewer.new_identity())
            self.assertEqual(stat.S_IMODE(directory.stat().st_mode), 0o700)
            self.assertEqual(stat.S_IMODE((directory / reviewer.FILENAME).stat().st_mode), 0o600)
            with self.assertRaises(reviewer.base.Failure):
                reviewer.new_private_directory(directory)
            link = root / 'link'; link.symlink_to(directory, target_is_directory=True)
            with self.assertRaises(reviewer.base.Failure):
                reviewer.new_private_directory(link)

    def test_success_retains_credentials_but_no_tokens_and_only_one_admin_write(self):
        with tempfile.TemporaryDirectory() as temp:
            directory = Path(temp).resolve(); state = reviewer.new_identity()
            api = FakeApi(directory, state)
            result = reviewer.create_and_verify(api, directory, state)
            self.assertTrue(result['non_admin_verified'])
            self.assertFalse(result['profile_setup_completed'])
            private = (directory / reviewer.FILENAME).read_text()
            self.assertIn(state['password'], private)
            self.assertNotIn('SYNTHETIC-TOKEN', private)
            self.assertNotIn('SYNTHETIC-REFRESH', private)
            self.assertNotIn(state['password'], json.dumps(result))
            self.assertNotIn(state['email'], json.dumps(result))
            admin_calls = [(p, k) for p, k in api.calls if k.get('service')]
            self.assertEqual(len(admin_calls), 1)
            self.assertEqual(admin_calls[0][0], '/auth/v1/admin/users')
            self.assertEqual(admin_calls[0][1]['method'], 'POST')
            self.assertFalse(any(k.get('method') in ('PATCH', 'PUT', 'DELETE') for _, k in api.calls))

    def test_admin_account_is_not_certified(self):
        with tempfile.TemporaryDirectory() as temp:
            directory = Path(temp).resolve(); state = reviewer.new_identity()
            with self.assertRaises(reviewer.base.Failure):
                reviewer.create_and_verify(FakeApi(directory, state, admin=True), directory, state)
            saved = json.loads((directory / reviewer.FILENAME).read_text())
            self.assertFalse(saved['non_admin_verified'])

    def test_unknown_creation_keeps_credentials_without_retry(self):
        with tempfile.TemporaryDirectory() as temp:
            directory = Path(temp).resolve(); state = reviewer.new_identity()
            api = FakeApi(directory, state, unknown_create=True)
            with self.assertRaises(reviewer.base.Failure):
                reviewer.create_and_verify(api, directory, state)
            self.assertEqual(len(api.calls), 1)
            saved = json.loads((directory / reviewer.FILENAME).read_text())
            self.assertEqual(saved['phase'], 'creating_account')
            self.assertEqual(saved['password'], state['password'])

    def test_live_error_output_never_echoes_exception_payload(self):
        output = io.StringIO()
        with patch.object(reviewer.base, 'load_config', side_effect=ValueError('SECRET-MUST-NOT-PRINT')), \
                contextlib.redirect_stdout(output):
            self.assertEqual(reviewer.main(['--execute']), 1)
        self.assertNotIn('SECRET-MUST-NOT-PRINT', output.getvalue())


if __name__ == '__main__':
    unittest.main()
