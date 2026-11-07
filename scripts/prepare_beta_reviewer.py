#!/usr/bin/env python3
"""Prepare one persistent, non-admin Apple beta reviewer on fixed staging.

Offline by default. --execute creates one email-confirmed test account without
sending email. Credentials stay in the fixed Git-external private directory.
No production target, role grants, profile/content writes or automatic cleanup.
An existing directory is never reused: ambiguous writes require manual review.
"""
import argparse
import json
import os
from pathlib import Path
import secrets
import stat
import sys
from datetime import datetime, timezone

sys.dont_write_bytecode = True
ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / 'tools/deployment/tests'))
import hosted_staging_acceptance as base

CONFIG = Path.home() / 'Night Owl Staging Access 2026-11-04/api.json'
DIRECTORY = Path.home() / 'Night Owl Review Access 2026-11-06'
FILENAME = 'reviewer.json'
PURPOSE = 'nightowl_apple_beta_review'
CA_FILE = '/etc/ssl/cert.pem'


def new_private_directory(path):
    path = Path(path).absolute()
    base.require(path == path.resolve() and
                 not any(p.is_symlink() for p in [path, *path.parents]), 'unsafe_review_directory')
    base.require(ROOT != path and ROOT not in path.parents and
                 not any((p / '.git').exists() or (p / '.git').is_symlink()
                         for p in [path, *path.parents]), 'review_directory_inside_git')
    parent = path.parent.stat()
    base.require(parent.st_uid == os.getuid() and not parent.st_mode & 0o022,
                 'unsafe_review_directory_parent')
    base.require(not path.exists(), 'review_directory_exists_reconcile_before_retry')
    os.mkdir(path, 0o700)
    mode = path.stat()
    base.require(stat.S_ISDIR(mode.st_mode) and stat.S_IMODE(mode.st_mode) == 0o700,
                 'review_directory_requires_0700')
    return path


def new_identity():
    marker = secrets.token_hex(12)
    return {
        'schema_version': 1, 'purpose': PURPOSE, 'project_ref': base.REF,
        'origin': base.ORIGIN, 'created_at_utc': datetime.now(timezone.utc).isoformat(),
        'marker': marker, 'email': f'nightowl-beta-review-{marker}@example.test',
        'password': secrets.token_urlsafe(32), 'user_id': None,
        'phase': 'prepared', 'persistent': True, 'non_admin_verified': False,
        'password_login_verified': False, 'profile_setup_completed': False,
        'representative_content_prepared': False,
    }


def create_body(state):
    return {'email': state['email'], 'password': state['password'], 'email_confirm': True,
            'user_metadata': {'username': 'beta_review_' + state['marker'][:8],
                              'nightowl_beta_review_marker': state['marker']}}


def create_and_verify(api, directory, state):
    def save(phase):
        state['phase'] = phase
        base.save_private(directory, FILENAME, state)

    save('creating_account')  # Keep recovery credentials before the first write.
    response = api.request('reviewer_create', '/auth/v1/admin/users', method='POST',
                           service=True, data=create_body(state))
    base.require(response.status in (200, 201), 'reviewer_create_failed_reconcile_before_retry')
    user = response.json()
    base.require(isinstance(user, dict) and base.UUID.fullmatch(user.get('id', '')) and
                 user.get('email') == state['email'] and user.get('role') == 'authenticated' and
                 user.get('user_metadata', {}).get('nightowl_beta_review_marker') == state['marker'] and
                 bool(user.get('email_confirmed_at')), 'created_reviewer_identity_mismatch')
    state['user_id'] = user['id']
    save('account_created')
    response = api.request('reviewer_login', '/auth/v1/token?grant_type=password', method='POST',
                           data={'email': state['email'], 'password': state['password']})
    base.require(response.status == 200, 'reviewer_password_login_failed')
    session = response.json()
    token = session.get('access_token')
    base.require(isinstance(token, str) and token and
                 session.get('user', {}).get('id') == state['user_id'], 'reviewer_session_mismatch')
    response = api.request('reviewer_identity', '/auth/v1/user', token=token)
    base.require(response.status == 200 and response.json().get('id') == state['user_id'],
                 'reviewer_identity_check_failed')
    uid = state['user_id']
    response = api.request('reviewer_profile',
                           f'/rest/v1/profiles?id=eq.{uid}&select=id,is_admin,is_banned,moderation_status',
                           token=token)
    base.require(response.status == 200, 'reviewer_profile_read_failed')
    rows = response.json()
    base.require(isinstance(rows, list) and len(rows) == 1 and rows[0].get('id') == uid and
                 rows[0].get('is_admin') is False and rows[0].get('is_banned') is not True,
                 'reviewer_profile_not_non_admin')
    response = api.request('reviewer_admin_check', '/rest/v1/rpc/social_admin',
                           method='POST', token=token, data={})
    base.require(response.status == 200 and response.json() is False, 'reviewer_has_admin_access')
    response = api.request('reviewer_active_check', '/rest/v1/rpc/social_active',
                           method='POST', token=token, data={})
    base.require(response.status == 200 and response.json() is True, 'reviewer_not_active')
    state['non_admin_verified'] = True
    state['password_login_verified'] = True
    save('account_verified_onboarding_pending')
    # Sessions stay in memory; only the persistent generated login is written.
    return {'status': state['phase'], 'project_ref': base.REF,
            'password_login_verified': True, 'non_admin_verified': True,
            'account_retained': True, 'profile_setup_completed': False,
            'representative_content_prepared': False, 'email_sent': False,
            'review_submission_performed': False}


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--execute', action='store_true')
    args = parser.parse_args(argv)
    if not args.execute:
        print(json.dumps({'offline_plan': True, 'project_ref': base.REF,
                          'config_file': str(CONFIG), 'private_directory': str(DIRECTORY),
                          'private_filename': FILENAME, 'account_creation_executed': False,
                          'persistent_non_admin_account': True, 'email_sent': False}))
        return 0
    try:
        config = base.load_config(CONFIG)
        directory = new_private_directory(DIRECTORY)
        state = new_identity()
        base.save_private(directory, FILENAME, state)
        api = base.Api(config, execute=True, ca_file=CA_FILE)
        result = create_and_verify(api, directory, state)
        print(json.dumps(result, sort_keys=True))
        return 0
    except base.Failure as error:
        print(json.dumps({'status': 'stopped', 'code': error.code,
                          'retain_private_state_for_manual_reconciliation': True}))
        return 1
    except Exception:
        print(json.dumps({'status': 'stopped', 'code': 'unexpected_error',
                          'retain_private_state_for_manual_reconciliation': True}))
        return 1


if __name__ == '__main__':
    raise SystemExit(main())
