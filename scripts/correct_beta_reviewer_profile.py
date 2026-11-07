#!/usr/bin/env python3
"""Correct only the fixed staging reviewer's username and fictional display name.

Offline by default. No Auth metadata, age, agreement, role, content or email
mutations. --execute reads the existing private reviewer file; no new account.
"""
import argparse
import json
from pathlib import Path
import re
import sys

sys.dont_write_bytecode = True
sys.path.insert(0, str(Path(__file__).resolve().parent))
import prepare_beta_reviewer as reviewer

base = reviewer.base
DISPLAY_NAME = 'Night Owl Review Demo'


def validate_state(state):
    base.require(isinstance(state, dict) and state.get('schema_version') == 1 and
                 state.get('purpose') == reviewer.PURPOSE and state.get('project_ref') == base.REF and
                 state.get('origin') == base.ORIGIN and state.get('persistent') is True and
                 state.get('phase') == 'account_verified_onboarding_pending' and
                 state.get('non_admin_verified') is True and state.get('password_login_verified') is True,
                 'wrong_private_reviewer_state')
    marker = state.get('marker', '')
    base.require(isinstance(marker, str) and re.fullmatch(r'[0-9a-f]{24}', marker) and
                 state.get('email') == f'nightowl-beta-review-{marker}@example.test' and
                 isinstance(state.get('password'), str) and
                 re.fullmatch(r'[A-Za-z0-9_-]{43}', state['password']) and
                 isinstance(state.get('user_id'), str) and base.UUID.fullmatch(state['user_id']),
                 'reviewer_identity_not_fixed')


def correct(api, state, directory):
    validate_state(state)
    response = api.request('correction_login', '/auth/v1/token?grant_type=password', method='POST',
                           data={'email': state['email'], 'password': state['password']})
    base.require(response.status == 200, 'correction_login_failed')
    session = response.json(); token = session.get('access_token')
    uid = state['user_id']
    base.require(isinstance(token, str) and token and session.get('user', {}).get('id') == uid,
                 'correction_session_mismatch')

    def user():
        reply = api.request('correction_identity', '/auth/v1/user', token=token)
        base.require(reply.status == 200, 'correction_auth_read_failed')
        value = reply.json()
        base.require(value.get('id') == uid and value.get('email') == state['email'] and
                     value.get('role') == 'authenticated' and
                     value.get('user_metadata', {}).get('nightowl_beta_review_marker') == state['marker'],
                     'correction_auth_identity_mismatch')
        return value

    before_metadata = user().get('user_metadata', {})
    columns = 'id,username,full_name,is_admin,is_banned,moderation_public_ready,moderation_version'
    response = api.request('correction_profile_read',
                           f'/rest/v1/profiles?id=eq.{uid}&select={columns}', token=token)
    base.require(response.status == 200, 'correction_profile_read_failed')
    rows = response.json()
    base.require(isinstance(rows, list) and len(rows) == 1, 'correction_profile_count')
    row = rows[0]
    base.require(row.get('id') == uid and row.get('is_admin') is False and
                 row.get('is_banned') is not True and row.get('moderation_public_ready') is False,
                 'correction_requires_new_non_admin_profile')
    response = api.request('correction_admin_check', '/rest/v1/rpc/social_admin',
                           method='POST', token=token, data={})
    base.require(response.status == 200 and response.json() is False, 'correction_admin_access')
    username = 'beta_review_' + state['marker'][:8]
    base.require(row.get('username') in ('beta-review-' + state['marker'][:12], username) and
                 row.get('full_name') in (None, '', DISPLAY_NAME), 'correction_unexpected_profile_content')
    if row.get('username') != username or row.get('full_name') != DISPLAY_NAME:
        version = row.get('moderation_version')
        base.require(isinstance(version, str) and base.UUID.fullmatch(version), 'invalid_profile_version')
        state['profile_correction_phase'] = 'patching'
        base.save_private(directory, reviewer.FILENAME, state)
        response = api.request('correction_profile_patch',
                               f'/rest/v1/profiles?id=eq.{uid}&moderation_version=eq.{version}&select={columns}',
                               method='PATCH', token=token,
                               data={'username': username, 'full_name': DISPLAY_NAME},
                               headers={'Prefer': 'return=representation'})
        base.require(response.status == 200, 'correction_patch_failed_reconcile')
        changed = response.json()
        base.require(isinstance(changed, list) and len(changed) == 1 and
                     changed[0].get('id') == uid and changed[0].get('username') == username and
                     changed[0].get('full_name') == DISPLAY_NAME and
                     changed[0].get('is_admin') is False and
                     changed[0].get('moderation_public_ready') is False, 'correction_result_mismatch')
    base.require(user().get('user_metadata', {}) == before_metadata, 'auth_metadata_changed_reconcile')
    state['profile_correction_phase'] = 'verified'
    state['profile_display_fields_corrected'] = True
    base.save_private(directory, reviewer.FILENAME, state)
    return {'status': 'profile_display_fields_corrected', 'project_ref': base.REF,
            'non_admin_verified': True, 'auth_metadata_unchanged': True,
            'adult_or_rules_attestation_performed': False, 'email_sent': False}


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--execute', action='store_true')
    args = parser.parse_args(argv)
    if not args.execute:
        print(json.dumps({'offline_plan': True, 'project_ref': base.REF,
                          'mutated_fields': ['profiles.username', 'profiles.full_name'],
                          'auth_metadata_mutation': False, 'account_creation': False}))
        return 0
    try:
        state = base.private_json(reviewer.DIRECTORY / reviewer.FILENAME)
        validate_state(state)
        config = base.load_config(reviewer.CONFIG)
        api = base.Api(config, execute=True, ca_file=reviewer.CA_FILE)
        print(json.dumps(correct(api, state, reviewer.DIRECTORY), sort_keys=True))
        return 0
    except base.Failure as error:
        print(json.dumps({'status': 'stopped', 'code': error.code}))
        return 1
    except Exception:
        print(json.dumps({'status': 'stopped', 'code': 'unexpected_error_reconcile_private_state'}))
        return 1


if __name__ == '__main__':
    raise SystemExit(main())
