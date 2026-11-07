import contextlib
import copy
import importlib.util
import io
import json
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch

SPEC = importlib.util.spec_from_file_location('correction', Path(__file__).resolve().parents[3] / 'scripts/correct_beta_reviewer_profile.py')
correction = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(correction)


def state():
    value = correction.reviewer.new_identity()
    value.update(user_id='12345678-1234-1234-1234-123456789abc',
                 phase='account_verified_onboarding_pending', non_admin_verified=True,
                 password_login_verified=True)
    return value


class Api:
    def __init__(self, value):
        self.state = value; self.calls = []
        self.metadata = {'nightowl_beta_review_marker': value['marker'],
                         'adult_confirmed': False, 'setup_complete': False,
                         'community_rules_version': 'not-accepted'}
        self.row = {'id': value['user_id'], 'username': 'beta-review-' + value['marker'][:12],
                    'full_name': None, 'is_admin': False, 'is_banned': False,
                    'moderation_public_ready': False,
                    'moderation_version': '22345678-1234-1234-1234-123456789abc'}

    def request(self, stage, path, **kwargs):
        self.calls.append((stage, path, kwargs))
        if stage == 'correction_login':
            result = {'access_token': 'SYNTHETIC-ONLY', 'user': {'id': self.state['user_id']}}
        elif stage == 'correction_identity':
            result = {'id': self.state['user_id'], 'email': self.state['email'],
                      'role': 'authenticated', 'user_metadata': copy.deepcopy(self.metadata)}
        elif stage == 'correction_profile_read':
            result = [dict(self.row)]
        elif stage == 'correction_admin_check':
            result = False
        elif stage == 'correction_profile_patch':
            self.row.update(kwargs['data']); result = [dict(self.row)]
        else:
            raise AssertionError('Unexpected request')
        return correction.base.Response(200, json.dumps(result).encode())


class CorrectionTests(unittest.TestCase):
    def test_offline_reads_no_private_files_and_creates_no_api(self):
        with patch.object(correction.base, 'private_json') as read, patch.object(correction.base, 'Api') as api, \
                contextlib.redirect_stdout(io.StringIO()):
            self.assertEqual(correction.main([]), 0)
        read.assert_not_called(); api.assert_not_called()

    def test_wrong_project_or_marker_rejected_before_network(self):
        for field in ('project_ref', 'email', 'marker', 'user_id'):
            value = state(); value[field] = 'invalid'
            api = Api(value)
            with self.assertRaises(correction.base.Failure):
                correction.correct(api, value, Path('/not-used'))
            self.assertEqual(api.calls, [])

    def test_only_two_profile_fields_change_and_agreements_stay_untouched(self):
        value = state(); api = Api(value); before = copy.deepcopy(api.metadata)
        with tempfile.TemporaryDirectory() as folder:
            result = correction.correct(api, value, Path(folder).resolve())
        self.assertEqual(api.metadata, before)
        patches = [entry for entry in api.calls if entry[2].get('method') == 'PATCH']
        self.assertEqual(len(patches), 1)
        self.assertEqual(set(patches[0][2]['data']), {'username', 'full_name'})
        self.assertIn('id=eq.' + value['user_id'], patches[0][1])
        self.assertIn('moderation_version=eq.', patches[0][1])
        self.assertFalse(any(entry[2].get('service') for entry in api.calls))
        self.assertTrue(result['auth_metadata_unchanged'])
        self.assertNotIn(value['password'], json.dumps(result))

    def test_wrong_remote_marker_admin_or_published_profile_stop_before_patch(self):
        for scenario in ('marker', 'admin', 'published', 'unexpected_name'):
            value = state(); api = Api(value)
            if scenario == 'marker': api.metadata['nightowl_beta_review_marker'] = 'wrong'
            if scenario == 'admin': api.row['is_admin'] = True
            if scenario == 'published': api.row['moderation_public_ready'] = True
            if scenario == 'unexpected_name': api.row['full_name'] = 'Unrelated existing name'
            with self.assertRaises(correction.base.Failure):
                correction.correct(api, value, Path('/not-used'))
            self.assertFalse(any(entry[2].get('method') == 'PATCH' for entry in api.calls))

    def test_repeated_correction_is_read_only(self):
        value = state(); api = Api(value)
        api.row.update(username='beta_review_' + value['marker'][:8], full_name=correction.DISPLAY_NAME)
        with tempfile.TemporaryDirectory() as folder:
            correction.correct(api, value, Path(folder).resolve())
        self.assertFalse(any(entry[2].get('method') == 'PATCH' for entry in api.calls))


if __name__ == '__main__':
    unittest.main()
