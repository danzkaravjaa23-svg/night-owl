import base64
from datetime import datetime, timedelta, timezone
import hashlib
import importlib.util
import json
from pathlib import Path
import plistlib
import subprocess
import sys
import tempfile
import unittest

TOOLS = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(TOOLS))
spec = importlib.util.spec_from_file_location('ios_signing', TOOLS / 'ios_signing.py')
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)


def jwt(ref='sreojqqqhdzkfsrbvlpl', role='anon'):
    encode = lambda value: base64.urlsafe_b64encode(json.dumps(value).encode()).decode().rstrip('=')
    return encode({'alg': 'HS256'}) + '.' + encode({'role': role, 'ref': ref, 'exp': 4102444800}) + '.c2lnbmF0dXJl'


def config(ref='sreojqqqhdzkfsrbvlpl'):
    return {'BACKEND_MODE': 'supabase', 'BACKEND_URL': f'https://{ref}.supabase.co', 'BACKEND_PUBLIC_KEY': jwt(ref)}


def profile():
    return {'UUID': '12345678-1234-1234-1234-123456789012', 'TeamIdentifier': [module.TEAM],
            'Platform': ['iOS'], 'ExpirationDate': datetime.now(timezone.utc) + timedelta(days=30),
            'DeveloperCertificates': [b'public-certificate-fixture'],
            'Entitlements': {'application-identifier': module.TEAM + '.' + module.BUNDLE,
                             'com.apple.developer.team-identifier': module.TEAM,
                             'get-task-allow': False, 'beta-reports-active': True,
                             'com.apple.developer.applesignin': ['Default']}}


class SigningTests(unittest.TestCase):
    def test_backend_and_anonymous_key_must_belong_to_selected_environment(self):
        self.assertEqual(module.public_config(config(), 'staging').url, config()['BACKEND_URL'])
        for values, environment in [(config(), 'production'),
                                    ({**config(), 'BACKEND_PUBLIC_KEY': jwt('jbbdnpsvstwxtgtjoeru')}, 'staging'),
                                    ({**config(), 'BACKEND_PUBLIC_KEY': jwt(role='service_role')}, 'staging'),
                                    ({**config(), 'DEVICE_PREVIEW': 'true'}, 'staging'),
                                    ({**config(), 'BACKEND_MODE': 'postgres'}, 'staging')]:
            with self.subTest(environment=environment, fields=tuple(values)):
                with self.assertRaises(ValueError):
                    module.public_config(values, environment)

    def test_expired_device_enterprise_or_other_team_profiles_rejected(self):
        for change in ({'ExpirationDate': datetime.now(timezone.utc) - timedelta(seconds=1)},
                       {'ProvisionedDevices': []}, {'ProvisionsAllDevices': True},
                       {'TeamIdentifier': ['OTHERTEAM1']}, {'Platform': ['OSX']}, {'UUID': '../escape'}):
            with self.subTest(fields=tuple(change)):
                with self.assertRaises(ValueError):
                    module.profile_metadata({**profile(), **change})

    def test_missing_apple_or_debug_entitlements_rejected(self):
        for change in ({'get-task-allow': True}, {'beta-reports-active': False},
                       {'application-identifier': module.TEAM + '.other.app'},
                       {'com.apple.developer.team-identifier': 'OTHERTEAM1'},
                       {'com.apple.developer.applesignin': []}):
            value = profile()
            value['Entitlements'].update(change)
            with self.subTest(fields=tuple(change)):
                with self.assertRaises(ValueError):
                    module.profile_metadata(value)

    def test_identity_must_be_valid_distribution_and_part_of_profile(self):
        value = profile()
        metadata = module.profile_metadata(value)
        fingerprint = metadata['certificate_sha1'][0]
        identity = f'1) {fingerprint} "Apple Distribution: Fixture ({module.TEAM})"'
        self.assertEqual(module.distribution_identity(identity, metadata), fingerprint)
        for invalid in ('0 valid identities found', identity.replace('Distribution', 'Development'),
                        identity.replace(module.TEAM, 'OTHERTEAM1'),
                        identity.replace(fingerprint, 'F' * 40)):
            with self.assertRaises(ValueError):
                module.distribution_identity(invalid, metadata)

    def test_export_is_manual_local_export_and_preserves_build_number(self):
        options = module.export_options(profile()['UUID'], 'A' * 40)
        self.assertEqual(options['destination'], 'export')
        self.assertEqual(options['signingStyle'], 'manual')
        self.assertEqual(options['teamID'], module.TEAM)
        self.assertFalse(options['manageAppVersionAndBuildNumber'])
        self.assertEqual(options['provisioningProfiles'], {module.BUNDLE: profile()['UUID']})

    def test_generated_build_configuration_cannot_switch_backend_or_enable_preview(self):
        parsed = module.public_config(config(), 'staging')
        values = {**parsed.public_defines(), 'DEVICE_PREVIEW': 'false'}
        def text(pairs):
            return 'DART_DEFINES=' + ','.join(base64.b64encode(f'{k}={v}'.encode()).decode() for k, v in pairs) + '\n'
        module.generated_defines(text(values.items()), parsed)
        for pairs in [list({**values, 'DEVICE_PREVIEW': 'true'}.items()),
                      list({**values, 'BACKEND_URL': 'https://other.example'}.items()),
                      list(values.items()) + [('DEVICE_PREVIEW', 'false')]]:
            with self.assertRaises(ValueError):
                module.generated_defines(text(pairs), parsed)

    def test_manual_profile_is_scoped_to_runner_not_cocoapods_targets(self):
        import re
        root = TOOLS.parents[1]
        project = (root / 'ios/Runner.xcodeproj/project.pbxproj').read_text()
        blocks = re.findall(r"^\t\t[0-9A-F]{24} /\*[^\n]*\*/ = \{(.*?)^\t\t\};",
                            project, re.MULTILINE | re.DOTALL)
        scoped = [block for block in blocks if 'NIGHTOWL_APP_PROFILE_UUID' in block]
        self.assertEqual(len(scoped), 3)
        for block in scoped:
            self.assertIn('INFOPLIST_FILE = Runner/Info.plist;', block)
            self.assertIn('PROVISIONING_PROFILE_SPECIFIER = "$(NIGHTOWL_APP_PROFILE_UUID)";', block)
        workflow = (root / '.github/workflows/ios-signed-candidate.yml').read_text()
        self.assertIn('NIGHTOWL_APP_PROFILE_UUID="$PROFILE_UUID"', workflow)
        self.assertNotIn('PROVISIONING_PROFILE_SPECIFIER=', workflow)
        self.assertNotIn('CODE_SIGNING_ALLOWED=YES', workflow)

    def test_build_number_rejects_shell_text_zero_or_missing(self):
        self.assertEqual(module.build_number('2'), '2')
        for value in ('', '0', '01', '1; curl example.test', '$(id)', '-1', '1.2'):
            with self.assertRaises(ValueError):
                module.build_number(value)

    def test_prepare_does_not_overwrite_and_receipt_contains_no_credential_or_certificate_bytes(self):
        with tempfile.TemporaryDirectory() as name:
            root = Path(name)
            value = profile()
            # plistlib's default writer uses UTC-naive profile dates.
            value['ExpirationDate'] = value['ExpirationDate'].replace(tzinfo=None)
            (root / 'profile.plist').write_bytes(plistlib.dumps(value))
            (root / 'config.json').write_text(json.dumps(config()))
            fingerprint = hashlib.sha1(value['DeveloperCertificates'][0]).hexdigest().upper()
            (root / 'identities.txt').write_text(f'1) {fingerprint} "Apple Distribution: Fixture ({module.TEAM})"')
            command = [sys.executable, str(TOOLS / 'ios_signing.py'), 'prepare', '--config', str(root / 'config.json'),
                       '--environment', 'staging', '--profile-plist', str(root / 'profile.plist'),
                       '--identities', str(root / 'identities.txt'), '--source-commit', '1' * 40,
                       '--build-number', '2', '--output', str(root / 'prepared')]
            result = subprocess.run(command, capture_output=True, text=True)
            self.assertEqual(result.returncode, 0, result.stderr)
            receipt = (root / 'prepared/input-receipt.json').read_text()
            self.assertNotIn(jwt(), receipt)
            self.assertNotIn('public-certificate-fixture', receipt)
            self.assertNotIn(jwt(), result.stdout + result.stderr)
            before = {p.name: p.read_bytes() for p in (root / 'prepared').iterdir()}
            repeated = subprocess.run(command, capture_output=True, text=True)
            self.assertNotEqual(repeated.returncode, 0)
            self.assertEqual(before, {p.name: p.read_bytes() for p in (root / 'prepared').iterdir()})


if __name__ == '__main__':
    unittest.main()
