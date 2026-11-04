#!/usr/bin/env python3
"""Validate existing manual-signing assets and an exported app; never provision/upload."""
import argparse
import base64
from datetime import datetime, timezone
import hashlib
import json
from pathlib import Path
import plistlib
import re
import subprocess

from build_admin_clients import BuildError, ClientConfig, CONFIG_KEYS

TEAM = 'DAVM2JZ4NN'
BUNDLE = 'com.nightowl.ub.nightOwlUb'
VERSION = '1.0.0'
PROJECTS = {'staging': 'sreojqqqhdzkfsrbvlpl', 'production': 'jbbdnpsvstwxtgtjoeru'}


def require(condition, message):
    if not condition:
        raise ValueError(message)


def public_config(values, environment):
    require(isinstance(values, dict) and set(values) == CONFIG_KEYS, 'Only the three public BACKEND settings are allowed')
    config = ClientConfig.parse(values, ('', ''))
    require(environment in PROJECTS, 'Unknown backend environment')
    ref = PROJECTS[environment]
    require(config.mode == 'supabase' and config.url == f'https://{ref}.supabase.co', 'Backend environment mismatch')
    segment = config.public_key.split('.')[1]
    claims = json.loads(base64.urlsafe_b64decode(segment + '=' * (-len(segment) % 4)))
    require(claims.get('ref') == ref, 'Anonymous key project mismatch')
    return config


def profile_metadata(profile, now=None):
    require(isinstance(profile, dict), 'Invalid provisioning profile')
    uuid = profile.get('UUID', '')
    require(isinstance(uuid, str) and re.fullmatch(r'[0-9A-Fa-f]{8}(?:-[0-9A-Fa-f]{4}){3}-[0-9A-Fa-f]{12}', uuid), 'Invalid profile UUID')
    require(profile.get('TeamIdentifier') == [TEAM], 'Wrong profile team')
    require('iOS' in profile.get('Platform', []), 'Profile is not for iOS')
    require('ProvisionedDevices' not in profile and not profile.get('ProvisionsAllDevices'), 'An App Store profile is required')
    expiry = profile.get('ExpirationDate')
    require(isinstance(expiry, datetime), 'Profile expiry is missing')
    expiry = expiry.replace(tzinfo=timezone.utc) if expiry.tzinfo is None else expiry
    require(expiry > (now or datetime.now(timezone.utc)), 'Provisioning profile expired')
    entitlement_metadata(profile.get('Entitlements', {}))
    require(profile['Entitlements'].get('beta-reports-active') is True, 'Profile is not App Store distribution')
    certificates = profile.get('DeveloperCertificates', [])
    require(certificates and all(isinstance(item, bytes) for item in certificates), 'Profile certificates missing')
    return {'uuid': uuid, 'expires_at': expiry.isoformat(),
            'certificate_sha1': [hashlib.sha1(item).hexdigest().upper() for item in certificates]}


def entitlement_metadata(entitlements):
    require(isinstance(entitlements, dict), 'Missing signing entitlements')
    require(entitlements.get('application-identifier') == f'{TEAM}.{BUNDLE}', 'Wrong signed app identifier')
    require(entitlements.get('com.apple.developer.team-identifier') == TEAM, 'Wrong signed team')
    require(entitlements.get('get-task-allow') is False, 'Debug entitlement must be false')
    require(entitlements.get('com.apple.developer.applesignin') == ['Default'], 'Apple login entitlement missing')


def distribution_identity(identities, metadata):
    matches = re.findall(r'\b([0-9A-Fa-f]{40}) "Apple Distribution: [^\n"]+ \(' + TEAM + r'\)"', identities)
    matches = [value.upper() for value in matches if value.upper() in metadata['certificate_sha1']]
    require(len(set(matches)) == 1, 'One valid Apple Distribution identity matching this profile is required')
    return matches[0]


def export_options(uuid, identity):
    return {'method': 'app-store-connect', 'destination': 'export', 'teamID': TEAM,
            'signingStyle': 'manual', 'signingCertificate': identity,
            'provisioningProfiles': {BUNDLE: uuid},
            'manageAppVersionAndBuildNumber': False, 'stripSwiftSymbols': True}


def build_number(value):
    require(bool(re.fullmatch(r'[1-9][0-9]{0,8}', value)), 'Positive build number required')
    return value


def generated_defines(text, config):
    lines = re.findall(r'^DART_DEFINES=(.*)$', text, re.MULTILINE)
    require(len(lines) == 1, 'Expected one generated DART_DEFINES entry')
    pairs = [base64.b64decode(value, validate=True).decode().split('=', 1) for value in lines[0].split(',')]
    require(all(len(pair) == 2 for pair in pairs), 'Invalid generated Dart define')
    values = dict(pairs)
    require(len(values) == len(pairs), 'Duplicate generated Dart defines')
    expected = {**config.public_defines(), 'DEVICE_PREVIEW': 'false'}
    require(all(values.get(key) == value for key, value in expected.items()), 'Generated build backend/preview mismatch')


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    sub = parser.add_subparsers(dest='action', required=True)
    prepare = sub.add_parser('prepare')
    for name in ('config', 'profile-plist', 'identities', 'output'):
        prepare.add_argument('--' + name, type=Path, required=True)
    prepare.add_argument('--environment', choices=PROJECTS, required=True)
    prepare.add_argument('--build-number', required=True)
    prepare.add_argument('--source-commit', required=True)
    prepare.add_argument('--github-output', type=Path)
    verify = sub.add_parser('verify')
    for name in ('app', 'prepared', 'generated-config', 'receipt'):
        verify.add_argument('--' + name, type=Path, required=True)
    args = parser.parse_args()
    try:
        if args.action == 'prepare':
            config = public_config(json.loads(args.config.read_text()), args.environment)
            metadata = profile_metadata(plistlib.loads(args.profile_plist.read_bytes()))
            identity = distribution_identity(args.identities.read_text(), metadata)
            number = build_number(args.build_number)
            require(bool(re.fullmatch(r'[0-9a-f]{40}', args.source_commit)), 'Exact source commit required')
            args.output.mkdir(parents=True, exist_ok=False)
            defines = json.dumps(config.public_defines(), indent=2) + '\n'
            (args.output / 'backend-defines.json').write_text(defines)
            (args.output / 'ExportOptions.plist').write_bytes(plistlib.dumps(export_options(metadata['uuid'], identity)))
            receipt = {'source_commit': args.source_commit, 'team_id': TEAM, 'bundle_id': BUNDLE,
                       'version': VERSION, 'build_number': number, 'environment': args.environment,
                       'backend_origin': config.url, 'device_preview': False,
                       'public_defines_sha256': hashlib.sha256(defines.encode()).hexdigest(),
                       'profile_uuid': metadata['uuid'], 'profile_expires_at': metadata['expires_at'],
                       'signing_identity_sha1': identity, 'status': 'inputs_prepared_not_build_success',
                       'upload_requested': False}
            (args.output / 'input-receipt.json').write_text(json.dumps(receipt, indent=2) + '\n')
            if args.github_output:
                with args.github_output.open('a') as stream:
                    stream.write(f"profile_uuid={metadata['uuid']}\nidentity_sha1={identity}\n")
            print('Validated existing distribution identity/profile and exact public backend config.')
        else:
            prepared = json.loads((args.prepared / 'input-receipt.json').read_text())
            config = public_config(json.loads((args.prepared / 'backend-defines.json').read_text()), prepared['environment'])
            generated_defines(args.generated_config.read_text(), config)
            info = plistlib.loads((args.app / 'Info.plist').read_bytes())
            require(info.get('CFBundleIdentifier') == BUNDLE, 'Exported bundle mismatch')
            require(info.get('CFBundleShortVersionString') == VERSION, 'Exported version mismatch')
            require(info.get('CFBundleVersion') == prepared['build_number'], 'Exported build number mismatch')
            subprocess.run(['codesign', '--verify', '--deep', '--strict', str(args.app)], check=True, capture_output=True)
            entitlements = subprocess.check_output(['codesign', '-d', '--entitlements', ':-', str(args.app)], stderr=subprocess.DEVNULL)
            entitlement_metadata(plistlib.loads(entitlements))
            raw_profile = subprocess.check_output(['security', 'cms', '-D', '-i', str(args.app / 'embedded.mobileprovision')], stderr=subprocess.DEVNULL)
            metadata = profile_metadata(plistlib.loads(raw_profile))
            require(metadata['uuid'] == prepared['profile_uuid'], 'Exported provisioning profile mismatch')
            require(prepared['signing_identity_sha1'] in metadata['certificate_sha1'], 'Exported profile certificate mismatch')
            privacy = sorted(args.app.rglob('PrivacyInfo.xcprivacy'))
            require((args.app / 'PrivacyInfo.xcprivacy') in privacy, 'Root privacy manifest missing')
            for file in privacy:
                plistlib.loads(file.read_bytes())
            receipt = {key: prepared[key] for key in ('source_commit', 'team_id', 'bundle_id', 'version', 'build_number', 'environment', 'backend_origin', 'device_preview', 'public_defines_sha256')}
            receipt.update(status='exported_app_signature_and_metadata_verified', privacy_manifests=len(privacy),
                           apple_login_tested=False, device_acceptance=False, app_store_uploaded=False)
            args.receipt.write_text(json.dumps(receipt, indent=2) + '\n')
            print('Exported app signature, Team, bundle, version, entitlement and generated backend config verified.')
    except (ValueError, TypeError, KeyError, OSError, BuildError, plistlib.InvalidFileException, subprocess.SubprocessError):
        parser.exit(2, 'iOS signing validation failed; inspect asset/config metadata privately. No credential values are logged.\n')


if __name__ == '__main__':
    main()
