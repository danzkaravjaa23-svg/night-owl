"""Offline security and recovery tests; never authenticate to Apple."""
import base64
import hashlib
import importlib.util
import io
import json
import os
from pathlib import Path
import plistlib
import socket
import subprocess
import tempfile
import unittest
from contextlib import redirect_stderr, redirect_stdout
from unittest.mock import patch
import zipfile

ROOT = Path(__file__).resolve().parents[3]
spec = importlib.util.spec_from_file_location('asc_upload', ROOT / 'scripts/app_store_connect_upload.py')
upload = importlib.util.module_from_spec(spec)
spec.loader.exec_module(upload)


def operation(offset=0, length=6):
    return {'offset': offset, 'length': length, 'method': 'PUT',
            'url': 'https://store-037.blobstore.apple.com/object?signature=DUMMY_ONLY',
            'requestHeaders': [{'name': 'Content-Type', 'value': 'application/octet-stream'}]}


class FakeTransport:
    def __init__(self):
        self.calls = []

    def request(self, method, url, headers, body, api):
        self.calls.append((method, url, headers, body, api))
        return b''


class FakeClient:
    def __init__(self, audience='INTERNAL_ONLY', fail_create=False, existing=False,
                 upload_ids=None, file_ids=None, processing=None, app_id=None, version=None):
        self.calls = []
        self.audience, self.fail_create, self.existing = audience, fail_create, existing
        self.upload_ids, self.file_ids = upload_ids or [], file_ids if file_ids is not None else ['file-1']
        self.processing = processing or ['VALID']
        self.app_id, self.version = app_id or upload.APP_ID, version or upload.VERSION

    def call(self, method, path, body=None):
        self.calls.append((method, path, body))
        if path == '/v1/apps/' + upload.APP_ID:
            return {'data': {'attributes': {'bundleId': upload.BUNDLE}}}
        if path.startswith('/v1/builds?'):
            return {'data': [{'id': 'existing-build'}] if self.existing else []}
        if '/apps/' in path and '/buildUploads?' in path:
            return {'data': [{'id': item} for item in self.upload_ids]}
        if method == 'POST' and path == '/v1/buildUploads':
            if self.fail_create:
                raise upload.UploadError('Simulated ambiguous HTTPS failure.')
            self.upload_ids.append('upload-1')
            return {'data': {'id': 'upload-1'}}
        if method == 'POST' and path == '/v1/buildUploadFiles':
            return {'data': {'id': 'file-1'}}
        if path == '/v1/buildUploads/upload-1/buildUploadFiles?limit=200':
            return {'data': [{'id': item} for item in self.file_ids]}
        if method == 'GET' and path == '/v1/buildUploadFiles/file-1':
            return {'data': {'id': 'file-1', 'attributes': {
                'fileSize': 6, 'assetType': 'ASSET',
                'assetDeliveryState': {'state': 'AWAITING_UPLOAD'},
                'uploadOperations': [operation(0, 3), operation(3, 3)]}}}
        if method == 'PATCH':
            return {'data': {'id': 'file-1'}}
        if path.startswith('/v1/buildUploads/upload-1?'):
            return {'data': {'attributes': {'cfBundleShortVersionString': upload.VERSION,
                'cfBundleVersion': upload.BUILD, 'platform': 'IOS', 'state': {'state': 'COMPLETE'}},
                'relationships': {'build': {'data': {'id': 'build-1'}}}}}
        if path.startswith('/v1/builds/build-1?'):
            processing = self.processing.pop(0) if len(self.processing) > 1 else self.processing[0]
            return {'data': {'attributes': {'version': upload.BUILD, 'processingState': processing,
                'buildAudienceType': self.audience}, 'relationships': {
                'app': {'data': {'id': self.app_id}}, 'preReleaseVersion': {'data': {'id': 'pre-1'}}}},
                'included': [{'type': 'preReleaseVersions', 'id': 'pre-1',
                              'attributes': {'version': self.version, 'platform': 'IOS'}}]}
        raise AssertionError('Unexpected fake API route: ' + method + ' ' + path)


class NetworkSafetyTests(unittest.TestCase):
    def test_rejects_non_apple_userinfo_local_insecure_and_redirect_targets(self):
        for url in ['http://store-037.blobstore.apple.com/a', 'https://127.0.0.1/a',
                    'https://store-037.blobstore.apple.com.evil.test/a',
                    'https://user@store-037.blobstore.apple.com/a',
                    'https://store-037.blobstore.apple.com:444/a',
                    'https://store-037.blobstore.apple.com/a#fragment']:
            with self.subTest(url=url), self.assertRaises(upload.UploadError):
                upload.validate_url(url)

    def test_rejects_private_dns_before_http(self):
        with patch.object(socket, 'getaddrinfo', return_value=[
                (socket.AF_INET, socket.SOCK_STREAM, 6, '', ('127.0.0.1', 443))]):
            with self.assertRaises(upload.UploadError):
                upload.public_address('api.appstoreconnect.apple.com')

    def test_no_bearer_or_signed_url_in_curl_argv_and_no_redirects(self):
        captured = {}
        def fake_run(command, **kwargs):
            captured.update(command=command, **kwargs)
            return subprocess.CompletedProcess(command, 0, b'{}\n200', b'')
        token = 'DUMMY_BEARER_SECRET'
        with patch.object(upload, 'public_address', return_value='17.1.2.3'), \
                patch.object(upload.subprocess, 'run', side_effect=fake_run):
            upload.CurlTransport().request('GET', upload.API + '/v1/apps/6830714135',
                                           {'Authorization': 'Bearer ' + token}, api=True)
        args = ' '.join(captured['command'])
        self.assertNotIn(token, args)
        self.assertNotIn(upload.API, args)
        self.assertNotIn('--location', args)
        self.assertNotIn('--insecure', args)
        self.assertEqual(captured['command'][1], '-q')
        self.assertIn(token.encode(), captured['input'])
        self.assertNotIn(token, str(captured['env']))

    def test_presigned_upload_rejects_authorization_header(self):
        with patch.object(upload, 'public_address', return_value='17.1.2.3'), \
                patch.object(upload.subprocess, 'run') as run:
            with self.assertRaises(upload.UploadError):
                upload.CurlTransport().request('PUT', operation()['url'],
                                               {'Authorization': 'Bearer DUMMY'}, b'abc')
            run.assert_not_called()

    def test_chunk_ranges_must_cover_whole_file_without_gaps_or_overlap(self):
        self.assertEqual(len(upload.operations_for_file([operation(3, 3), operation(0, 3)], 6)), 2)
        for ops in [[operation(0, 2), operation(3, 3)], [operation(0, 4), operation(3, 3)],
                    [operation(0, 7)], [], [operation(False, 6)]]:
            with self.assertRaises(upload.UploadError):
                upload.operations_for_file(ops, 6)


class WorkflowTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.path = Path(self.temp.name) / 'state.json'
        self.raw = b'abcdef'
        p1 = patch.object(upload, 'IPA_SIZE', 6)
        p2 = patch.object(upload, 'SHA256', hashlib.sha256(self.raw).hexdigest())
        p1.start(); p2.start()
        self.addCleanup(p1.stop); self.addCleanup(p2.stop)

    def test_full_workflow_uses_apple_commit_shape_and_verifies_internal_server_build(self):
        client, transport = FakeClient(), FakeTransport()
        result = upload.run_upload(client, transport, upload.Journal(self.path), self.raw,
                                   'test.ipa', poll_seconds=0)
        self.assertEqual(result['phase'], 'complete')
        self.assertTrue(result['app_store_uploaded'])
        self.assertFalse(result['app_review_submitted'])
        self.assertEqual(b''.join(c[3] for c in transport.calls), self.raw)
        self.assertTrue(all(not c[4] and 'Authorization' not in c[2] for c in transport.calls))
        commit = next(body for method, _, body in client.calls if method == 'PATCH')
        self.assertEqual(commit['data']['attributes'], {'uploaded': True})
        state_text = self.path.read_text()
        self.assertNotIn('signature=', state_text)
        self.assertNotIn('uploadOperations', state_text)
        self.assertEqual(self.path.stat().st_mode & 0o777, 0o600)

    def test_no_write_when_build_already_exists(self):
        client = FakeClient(existing=True)
        with self.assertRaises(upload.UploadError):
            upload.run_upload(client, FakeTransport(), upload.Journal(self.path), self.raw, 'test.ipa')
        self.assertTrue(all(method == 'GET' for method, _, _ in client.calls))

    def test_saved_upload_must_belong_to_app_even_when_a_build_exists(self):
        journal = upload.Journal(self.path)
        journal.save(upload_id='wrong-upload', file_id='file-1', phase='file_reserved')
        client, transport = FakeClient(existing=True), FakeTransport()
        with self.assertRaises(upload.UploadError):
            upload.run_upload(client, transport, journal, self.raw, 'test.ipa')
        self.assertTrue(all(method == 'GET' for method, _, _ in client.calls))
        self.assertEqual(transport.calls, [])

    def test_saved_file_must_belong_to_upload_before_any_write(self):
        journal = upload.Journal(self.path)
        journal.save(upload_id='upload-1', file_id='file-1', phase='file_reserved')
        client, transport = FakeClient(upload_ids=['upload-1'], file_ids=['different-file']), FakeTransport()
        with self.assertRaises(upload.UploadError):
            upload.run_upload(client, transport, journal, self.raw, 'test.ipa')
        self.assertTrue(all(method == 'GET' for method, _, _ in client.calls))
        self.assertEqual(transport.calls, [])

    def test_build_processing_is_polled_until_valid(self):
        client = FakeClient(processing=['PROCESSING', 'VALID'])
        sleeps = []
        result = upload.run_upload(client, FakeTransport(), upload.Journal(self.path), self.raw,
                                   'test.ipa', poll_seconds=30, sleep=sleeps.append)
        self.assertEqual(result['phase'], 'complete')
        self.assertEqual(sleeps, [10])

    def test_processed_build_must_match_app_and_marketing_version(self):
        for values in [{'app_id': '999'}, {'version': '9.0.0'}]:
            with self.subTest(values=values):
                if self.path.exists():
                    self.path.unlink()
                with self.assertRaises(upload.UploadError):
                    upload.run_upload(FakeClient(**values), FakeTransport(), upload.Journal(self.path),
                                      self.raw, 'test.ipa', poll_seconds=0)
                self.assertNotEqual(json.loads(self.path.read_text())['phase'], 'complete')

    def test_ambiguous_create_is_not_repeated_on_resume(self):
        first = FakeClient(fail_create=True)
        with self.assertRaises(upload.UploadError):
            upload.run_upload(first, FakeTransport(), upload.Journal(self.path), self.raw, 'test.ipa')
        self.assertEqual(json.loads(self.path.read_text())['phase'], 'creating_upload')
        second = FakeClient()
        with self.assertRaises(upload.UploadError):
            upload.run_upload(second, FakeTransport(), upload.Journal(self.path), self.raw, 'test.ipa')
        self.assertTrue(all(method == 'GET' for method, _, _ in second.calls))

    def test_ambiguous_commit_is_not_repeated_without_manual_reconciliation(self):
        journal = upload.Journal(self.path)
        journal.save(upload_id='upload-1', file_id='file-1', phase='committing_file')
        client, transport = FakeClient(upload_ids=['upload-1']), FakeTransport()
        with self.assertRaises(upload.UploadError):
            upload.run_upload(client, transport, journal, self.raw, 'test.ipa', poll_seconds=0)
        self.assertTrue(all(method == 'GET' for method, _, _ in client.calls))
        self.assertEqual(transport.calls, [])
        self.assertEqual(upload.Journal(self.path).data['phase'], 'committing_file')

    def test_app_store_eligible_audience_cannot_be_reported_as_success(self):
        with self.assertRaises(upload.UploadError):
            upload.run_upload(FakeClient(audience='APP_STORE_ELIGIBLE'), FakeTransport(),
                              upload.Journal(self.path), self.raw, 'test.ipa', poll_seconds=0)
        self.assertNotEqual(json.loads(self.path.read_text())['phase'], 'complete')

    def test_wrong_ipa_bytes_do_not_contact_apple(self):
        client = FakeClient()
        with self.assertRaises(upload.UploadError):
            upload.run_upload(client, FakeTransport(), upload.Journal(self.path), b'changed', 'test.ipa')
        self.assertEqual(client.calls, [])

    def test_simultaneous_state_lock_is_rejected(self):
        with upload.exclusive_state(self.path):
            with self.assertRaises(upload.UploadError):
                with upload.exclusive_state(self.path):
                    self.fail('Second process acquired lock')


class JWTTests(unittest.TestCase):
    def test_short_lived_individual_jwt_and_mutation_claims(self):
        from cryptography.hazmat.primitives import serialization
        from cryptography.hazmat.primitives.asymmetric import ec
        key = ec.generate_private_key(ec.SECP256R1())
        with tempfile.TemporaryDirectory() as folder:
            path = Path(folder) / 'test-only.p8'
            path.write_bytes(key.private_bytes(serialization.Encoding.PEM,
                serialization.PrivateFormat.PKCS8, serialization.NoEncryption()))
            path.chmod(0o600)
            signer = upload.JWTSigner(path, 'DUMMYKEY01', individual=True)
            for method, path_text in [
                    ('GET', '/v1/apps/6830714135'),
                    ('GET', '/v1/builds?filter%5Bapp%5D=6830714135&limit=200'),
                    ('GET', '/v1/apps/6830714135/buildUploads?filter%5Bplatform%5D=IOS'),
                    ('POST', '/v1/buildUploads'), ('PATCH', '/v1/buildUploadFiles/file-1')]:
                with self.subTest(method=method, path=path_text):
                    token = signer.token(method, path_text)
                    claims = json.loads(base64.urlsafe_b64decode(token.split('.')[1] + '=='))
                    self.assertEqual(claims['exp'] - claims['iat'], 300)
                    self.assertEqual(claims['sub'], 'user')
                    self.assertNotIn('iss', claims)
                    self.assertNotIn('scope', claims)
            path.chmod(0o644)
            with self.assertRaises(upload.UploadError):
                upload.JWTSigner(path, 'DUMMYKEY01', individual=True)


class CandidateProfileTests(unittest.TestCase):
    def test_default_is_offline_internal_build1_without_credentials_or_state(self):
        stream = io.StringIO()
        expected_path = upload.DEFAULT_IPA
        with patch.object(upload, 'validate_artifact', return_value=b'verified') as validate, \
                patch.object(upload, 'JWTSigner') as signer, \
                patch.object(upload, 'CurlTransport') as transport, \
                patch.object(upload, 'Journal') as journal, redirect_stdout(stream):
            self.assertEqual(upload.main([]), 0)
        validate.assert_called_once_with(expected_path)
        signer.assert_not_called(); transport.assert_not_called(); journal.assert_not_called()
        result = json.loads(stream.getvalue())
        self.assertEqual(result['candidate_profile'], 'internal-staging-1')
        self.assertEqual(result['expected_build_audience'], 'INTERNAL_ONLY')
        self.assertEqual(result['proposed_create_request']['data']['attributes']['cfBundleVersion'], '1')

    def test_external_profile_has_separate_fixed_artifact_and_journal(self):
        old_path, old_state, old_hash = upload.DEFAULT_IPA, upload.DEFAULT_STATE, upload.SHA256
        with upload.candidate_profile('external-staging-2'):
            self.assertEqual(upload.BUILD, '2')
            self.assertEqual(upload.IPA_SIZE, 33639969)
            self.assertEqual(upload.EXPECTED_AUDIENCE, 'APP_STORE_ELIGIBLE')
            self.assertFalse(upload.INTERNAL_ONLY)
            self.assertNotEqual(upload.DEFAULT_IPA, old_path)
            self.assertNotEqual(upload.DEFAULT_STATE, old_state)
            self.assertNotEqual(upload.SHA256, old_hash)
        self.assertEqual(upload.DEFAULT_IPA, old_path)
        self.assertEqual(upload.BUILD, '1')

    def test_build3_pins_new_artifact_and_rejects_build2_journal(self):
        with tempfile.TemporaryDirectory() as folder:
            path = Path(folder) / 'state.json'
            with upload.candidate_profile('external-staging-2'):
                previous_path, previous_hash = upload.DEFAULT_IPA, upload.SHA256
                previous_state = upload.DEFAULT_STATE
                upload.Journal(path).save(phase='new')
            with upload.candidate_profile('external-staging-3'):
                self.assertEqual(upload.BUILD, '3')
                self.assertEqual(upload.IPA_SIZE, 33646028)
                self.assertEqual(upload.SHA256, '0cccb95a1d11c8d9090ad9a5f35d1351eeeaf74d3318913570b0a9bfd33526e3')
                self.assertEqual(upload.EXPECTED_AUDIENCE, 'APP_STORE_ELIGIBLE')
                self.assertFalse(upload.INTERNAL_ONLY)
                self.assertNotEqual(upload.DEFAULT_IPA, previous_path)
                self.assertNotEqual(upload.SHA256, previous_hash)
                self.assertNotEqual(upload.DEFAULT_STATE, previous_state)
                with self.assertRaises(upload.UploadError):
                    upload.Journal(path)
                self.assertEqual(upload.create_upload_body()['data']['attributes'],
                    {'cfBundleShortVersionString': '1.0.0', 'cfBundleVersion': '3', 'platform': 'IOS'})
            self.assertEqual(upload.BUILD, '1')

    def test_build4_pins_new_artifact_and_rejects_build3_journal(self):
        with tempfile.TemporaryDirectory() as folder:
            path = Path(folder) / 'state.json'
            with upload.candidate_profile('external-staging-3'):
                previous_path, previous_hash = upload.DEFAULT_IPA, upload.SHA256
                previous_state = upload.DEFAULT_STATE
                upload.Journal(path).save(phase='new')
            with upload.candidate_profile('external-staging-4'):
                self.assertEqual(upload.BUILD, '4')
                self.assertEqual(upload.IPA_SIZE, 33649006)
                self.assertEqual(upload.SHA256, '3aef80816d0e9e7f045ae89e652522de8f0d41d0a2cb61449e9299dd215ac6b7')
                self.assertEqual(upload.EXPECTED_AUDIENCE, 'APP_STORE_ELIGIBLE')
                self.assertFalse(upload.INTERNAL_ONLY)
                self.assertNotEqual(upload.DEFAULT_IPA, previous_path)
                self.assertNotEqual(upload.SHA256, previous_hash)
                self.assertNotEqual(upload.DEFAULT_STATE, previous_state)
                with self.assertRaises(upload.UploadError):
                    upload.Journal(path)
                self.assertEqual(upload.create_upload_body()['data']['attributes'],
                    {'cfBundleShortVersionString': '1.0.0', 'cfBundleVersion': '4', 'platform': 'IOS'})
            self.assertEqual(upload.BUILD, '1')

    def test_build5_pins_new_artifact_and_rejects_build4_journal(self):
        with tempfile.TemporaryDirectory() as folder:
            path = Path(folder) / 'state.json'
            with upload.candidate_profile('external-staging-4'):
                previous_path, previous_hash = upload.DEFAULT_IPA, upload.SHA256
                upload.Journal(path).save(phase='new')
            with upload.candidate_profile('external-staging-5'):
                self.assertEqual(upload.BUILD, '5')
                self.assertEqual(upload.IPA_SIZE, 33646148)
                self.assertEqual(upload.SHA256, '1ee602efc876adbf520fb9984072b488483a7a929e7344fc5c7ca3c91a97368f')
                self.assertEqual(upload.EXPECTED_AUDIENCE, 'APP_STORE_ELIGIBLE')
                self.assertNotEqual(upload.DEFAULT_IPA, previous_path)
                self.assertNotEqual(upload.SHA256, previous_hash)
                with self.assertRaises(upload.UploadError):
                    upload.Journal(path)
                self.assertEqual(upload.create_upload_body()['data']['attributes'],
                    {'cfBundleShortVersionString': '1.0.0', 'cfBundleVersion': '5', 'platform': 'IOS'})
            self.assertEqual(upload.BUILD, '1')

    def test_build3_external_workflow_verifies_exact_remote_build_number(self):
        raw = b'abcdef'
        with tempfile.TemporaryDirectory() as folder, upload.candidate_profile('external-staging-3'), \
                patch.object(upload, 'IPA_SIZE', len(raw)), \
                patch.object(upload, 'SHA256', hashlib.sha256(raw).hexdigest()):
            result = upload.run_upload(FakeClient(audience='APP_STORE_ELIGIBLE'), FakeTransport(),
                upload.Journal(Path(folder) / 'state.json'), raw, 'test.ipa', poll_seconds=0)
            self.assertEqual(result['build_number'], '3')
            self.assertEqual(result['build_audience'], 'APP_STORE_ELIGIBLE')
            self.assertFalse(result['publicly_released'])
            self.assertFalse(result['app_review_submitted'])

    def test_internal_and_external_journals_cannot_be_interchanged(self):
        with tempfile.TemporaryDirectory() as folder:
            path = Path(folder) / 'state.json'
            upload.Journal(path).save(phase='new')
            with upload.candidate_profile('external-staging-2'), self.assertRaises(upload.UploadError):
                upload.Journal(path)
            path.unlink()
            with upload.candidate_profile('external-staging-2'):
                upload.Journal(path).save(phase='new')
            with self.assertRaises(upload.UploadError):
                upload.Journal(path)

    def test_profile_rejects_wrong_internal_marker_even_for_otherwise_pinned_bytes(self):
        with tempfile.TemporaryDirectory() as folder:
            path = Path(folder) / 'synthetic-test-only.ipa'
            for profile, wrong_marker in [('internal-staging-1', False), ('external-staging-2', True)]:
                with self.subTest(profile=profile), upload.candidate_profile(profile):
                    with zipfile.ZipFile(path, 'w') as archive:
                        archive.writestr('Payload/Runner.app/Info.plist', plistlib.dumps({
                            'CFBundleIdentifier': upload.BUNDLE, 'CFBundleShortVersionString': upload.VERSION,
                            'CFBundleVersion': upload.BUILD, 'TFInternalTestingOnly': wrong_marker}))
                    raw = path.read_bytes()
                    with patch.object(upload, 'IPA_SIZE', len(raw)), \
                            patch.object(upload, 'SHA256', hashlib.sha256(raw).hexdigest()), \
                            self.assertRaises(upload.UploadError):
                        upload.validate_artifact(path)

    def test_external_success_requires_external_audience_and_never_claims_release(self):
        raw = b'abcdef'
        with tempfile.TemporaryDirectory() as folder, upload.candidate_profile('external-staging-2'), \
                patch.object(upload, 'IPA_SIZE', len(raw)), \
                patch.object(upload, 'SHA256', hashlib.sha256(raw).hexdigest()):
            result = upload.run_upload(FakeClient(audience='APP_STORE_ELIGIBLE'), FakeTransport(),
                upload.Journal(Path(folder) / 'correct.json'), raw, 'test.ipa', poll_seconds=0)
            self.assertEqual(result['build_number'], '2')
            self.assertEqual(result['build_audience'], 'APP_STORE_ELIGIBLE')
            self.assertFalse(result['publicly_released'])
            self.assertFalse(result['app_review_submitted'])
            with self.assertRaises(upload.UploadError):
                upload.run_upload(FakeClient(audience='INTERNAL_ONLY'), FakeTransport(),
                    upload.Journal(Path(folder) / 'wrong.json'), raw, 'test.ipa', poll_seconds=0)

    def test_arbitrary_artifact_and_state_paths_are_not_cli_options(self):
        for option in ['--ipa', '--state', '--sha256']:
            with self.subTest(option=option), redirect_stderr(io.StringIO()), self.assertRaises(SystemExit) as result:
                upload.main([option, '/tmp/not-a-candidate'])
            self.assertEqual(result.exception.code, 2)


if __name__ == '__main__':
    unittest.main()
