#!/usr/bin/env python3
"""Upload a fixed, verified Night Owl staging IPA. Offline validation is default.

Apple API 4.1 schemas: BuildUploadCreateRequest, BuildUploadFileCreateRequest,
BuildUploadFileUpdateRequest, Checksums and DeliveryFileUploadOperation.
https://developer.apple.com/documentation/appstoreconnectapi/build-uploads

No credentials are read unless --upload is explicitly supplied. No App Review,
tester, encryption-attestation, account, or credential mutations are supported.
"""
import argparse
import base64
import contextlib
import fcntl
import hashlib
import ipaddress
import json
import os
from pathlib import Path
import plistlib
import re
import socket
import stat
import subprocess
import tempfile
import time
from urllib.parse import urlencode, urlsplit
import zipfile

ROOT = Path(__file__).resolve().parents[1]
CANDIDATE = ROOT / 'build/ios-signing/878a941966aa06baf8a03dcf99d33464fc9d2b88-1.0.0-1-staging'
DEFAULT_IPA = CANDIDATE / 'internal-only/export/night_owl_ub.ipa'
APP_ID = '6830714135'
BUNDLE = 'com.nightowl.ub.nightOwlUb'
TEAM = 'DAVM2JZ4NN'
VERSION, BUILD = '1.0.0', '1'
SHA256 = '1f1c2842db3408a86b88156f51bee4dcaa87f452e334e27178ac1c633dcef0b5'
IPA_SIZE = 33639829
DEFAULT_STATE = CANDIDATE / 'internal-only/direct-upload-state.json'
INTERNAL_ONLY = True
EXPECTED_AUDIENCE = 'INTERNAL_ONLY'
EXTERNAL_CANDIDATE = ROOT / 'build/ios-signing/67e8b1c79764285df6cd21981e066b62790eac70-1.0.0-2-staging-external'
EXTERNAL_CANDIDATE_3 = ROOT / 'build/ios-signing/d56e6efcf10dd98d567a388e05aa4c52a3393a65-1.0.0-3-staging-external'
EXTERNAL_CANDIDATE_4 = ROOT / 'build/ios-signing/b2d58f21c53b3d416bd6d20a6b9ec4ea20dd201e-1.0.0-4-staging-external'
EXTERNAL_CANDIDATE_5 = ROOT / 'build/ios-signing/b6485747d75594ceb09f43442eb6aea7dabaae90-1.0.0-5-staging-external'
PROFILES = {
    'internal-staging-1': {
        'CANDIDATE': CANDIDATE, 'DEFAULT_IPA': DEFAULT_IPA, 'DEFAULT_STATE': DEFAULT_STATE,
        'BUILD': BUILD, 'SHA256': SHA256, 'IPA_SIZE': IPA_SIZE,
        'INTERNAL_ONLY': True, 'EXPECTED_AUDIENCE': 'INTERNAL_ONLY'},
    'external-staging-2': {
        'CANDIDATE': EXTERNAL_CANDIDATE,
        'DEFAULT_IPA': EXTERNAL_CANDIDATE / 'export/night_owl_ub.ipa',
        'DEFAULT_STATE': EXTERNAL_CANDIDATE / 'direct-upload-state.json',
        'BUILD': '2', 'SHA256': '6a226eed784a60a4136405df6598106e3545e4c0b315acb64905ce9176b7cfda',
        'IPA_SIZE': 33639969, 'INTERNAL_ONLY': False, 'EXPECTED_AUDIENCE': 'APP_STORE_ELIGIBLE'},
    'external-staging-3': {
        'CANDIDATE': EXTERNAL_CANDIDATE_3,
        'DEFAULT_IPA': EXTERNAL_CANDIDATE_3 / 'export/night_owl_ub.ipa',
        'DEFAULT_STATE': EXTERNAL_CANDIDATE_3 / 'direct-upload-state.json',
        'BUILD': '3', 'SHA256': '0cccb95a1d11c8d9090ad9a5f35d1351eeeaf74d3318913570b0a9bfd33526e3',
        'IPA_SIZE': 33646028, 'INTERNAL_ONLY': False, 'EXPECTED_AUDIENCE': 'APP_STORE_ELIGIBLE'},
    'external-staging-4': {
        'CANDIDATE': EXTERNAL_CANDIDATE_4,
        'DEFAULT_IPA': EXTERNAL_CANDIDATE_4 / 'export/night_owl_ub.ipa',
        'DEFAULT_STATE': EXTERNAL_CANDIDATE_4 / 'direct-upload-state.json',
        'BUILD': '4', 'SHA256': '3aef80816d0e9e7f045ae89e652522de8f0d41d0a2cb61449e9299dd215ac6b7',
        'IPA_SIZE': 33649006, 'INTERNAL_ONLY': False, 'EXPECTED_AUDIENCE': 'APP_STORE_ELIGIBLE'},
    'external-staging-5': {
        'CANDIDATE': EXTERNAL_CANDIDATE_5,
        'DEFAULT_IPA': EXTERNAL_CANDIDATE_5 / 'export/night_owl_ub.ipa',
        'DEFAULT_STATE': EXTERNAL_CANDIDATE_5 / 'direct-upload-state.json',
        'BUILD': '5', 'SHA256': '1ee602efc876adbf520fb9984072b488483a7a929e7344fc5c7ca3c91a97368f',
        'IPA_SIZE': 33646148, 'INTERNAL_ONLY': False, 'EXPECTED_AUDIENCE': 'APP_STORE_ELIGIBLE'},
}
API_HOST = 'api.appstoreconnect.apple.com'
API = 'https://' + API_HOST
UPLOAD_HOSTS = {'northamerica-1.object-storage.apple.com', *{
    'store-' + n + '.blobstore.apple.com' for n in
    ['037', '036', '035', '033', '032', '030', '028', '026', '025', '004']}}


class UploadError(Exception):
    """Messages contain no server payloads, credentials or signed URLs."""


def require(condition, message):
    if not condition:
        raise UploadError(message)


@contextlib.contextmanager
def candidate_profile(name):
    """Select fixed constants for this single-process command, then restore them."""
    require(name in PROFILES, 'Unknown fixed candidate profile.')
    values = PROFILES[name]
    previous = {key: globals()[key] for key in values}
    globals().update(values)
    try:
        yield
    finally:
        globals().update(previous)


def identifier(value):
    require(isinstance(value, str) and re.fullmatch(r'[A-Za-z0-9-]{1,100}', value),
            'Invalid resource identifier; stopped safely.')
    return value


def validate_artifact(path):
    require(path.is_file() and not path.is_symlink(), 'IPA must be a regular file.')
    raw = path.read_bytes()
    require(len(raw) == IPA_SIZE and hashlib.sha256(raw).hexdigest() == SHA256,
            'IPA differs from the selected verified candidate.')
    with zipfile.ZipFile(path) as archive:
        info = plistlib.loads(archive.read('Payload/Runner.app/Info.plist'))
    marker = info.get('TFInternalTestingOnly')
    marker_matches = marker is True if INTERNAL_ONLY else marker is None or marker is False
    require(info.get('CFBundleIdentifier') == BUNDLE and
            info.get('CFBundleShortVersionString') == VERSION and
            info.get('CFBundleVersion') == BUILD and
            marker_matches,
            'IPA identity or internal-only marker mismatch.')
    # The fixed digest pins the already-verified Team DAVM2JZ4NN signature/profile.
    return raw


def create_upload_body():
    return {'data': {'type': 'buildUploads', 'attributes': {
        'cfBundleShortVersionString': VERSION, 'cfBundleVersion': BUILD,
        'platform': 'IOS'}, 'relationships': {
            'app': {'data': {'type': 'apps', 'id': APP_ID}}}}}


def reserve_file_body(upload_id, file_name):
    return {'data': {'type': 'buildUploadFiles', 'attributes': {
        'assetType': 'ASSET', 'fileName': file_name, 'fileSize': IPA_SIZE,
        'uti': 'com.apple.ipa'}, 'relationships': {'buildUpload': {
            'data': {'type': 'buildUploads', 'id': identifier(upload_id)}}}}}


def commit_file_body(file_id):
    # Match Apple's upload-testflight-build completeBuildUpload implementation.
    # Optional sourceFileChecksums is rejected by the live IPA endpoint; the
    # fixed SHA256 above still validates every byte before any network operation.
    return {'data': {'type': 'buildUploadFiles', 'id': identifier(file_id),
                     'attributes': {'uploaded': True}}}


def validate_url(url, api=False):
    require(isinstance(url, str) and not any(ord(c) < 33 for c in url),
            'Unsafe URL rejected.')
    parsed = urlsplit(url)
    try:
        port = parsed.port
    except ValueError:
        raise UploadError('Unsafe URL rejected.') from None
    require(parsed.scheme == 'https' and not parsed.username and not parsed.password
            and port in (None, 443) and not parsed.fragment, 'Unsafe URL rejected.')
    allowed = {API_HOST} if api else UPLOAD_HOSTS
    require(parsed.hostname in allowed, 'Unexpected destination host rejected.')
    if api:
        require(parsed.path.startswith('/v1/'), 'Unexpected API path rejected.')
    return parsed


def public_address(host):
    addresses = socket.getaddrinfo(host, 443, type=socket.SOCK_STREAM)
    addresses.sort(key=lambda value: value[0] != socket.AF_INET)
    for _, _, _, _, addr in addresses:
        ip = ipaddress.ip_address(addr[0])
        if ip.is_global:
            return str(ip)
    raise UploadError('Destination resolved to no public address.')


def config_quote(value):
    require(not any(c in value for c in '\r\n\x00'), 'Unsafe curl configuration value.')
    return '"' + value.replace('\\', '\\\\').replace('"', '\\"') + '"'


class CurlTransport:
    """Strict TLS, no redirects/proxies/curlrc, secrets only on a private pipe."""
    def request(self, method, url, headers=None, body=b'', api=False):
        parsed = validate_url(url, api)
        require(method in ('GET', 'POST', 'PATCH', 'PUT'), 'Unsupported HTTP method.')
        address = public_address(parsed.hostname)
        resolved = '[' + address + ']' if ':' in address else address
        config = ['url = ' + config_quote(url), 'request = ' + config_quote(method),
                  'resolve = ' + config_quote(parsed.hostname + ':443:' + resolved)]
        for name, value in (headers or {}).items():
            require(re.fullmatch(r'[A-Za-z0-9-]+', name), 'Invalid header name.')
            if not api:
                require(name.lower() not in {
                    'authorization', 'proxy-authorization', 'cookie', 'host',
                    'connection', 'transfer-encoding'}, 'Unsafe upload header rejected.')
            config.append('header = ' + config_quote(name + ': ' + value))
        env = {k: v for k, v in os.environ.items() if k.lower() not in {
            'http_proxy', 'https_proxy', 'all_proxy', 'no_proxy', 'curl_ca_bundle',
            'ssl_cert_file', 'ssl_cert_dir', 'sslkeylogfile'}}
        with tempfile.TemporaryFile() as payload:
            payload.write(body)
            payload.seek(0)
            if method != 'GET':
                config.append('data-binary = ' + config_quote('@/dev/fd/' + str(payload.fileno())))
            command = ['/usr/bin/curl', '-q', '--config', '-', '--silent', '--show-error',
                       '--proto', '=https', '--tlsv1.2', '--cacert', '/etc/ssl/cert.pem',
                       '--noproxy', '*', '--max-redirs', '0', '--connect-timeout', '30',
                       '--max-time', '180', '--max-filesize', '8388608',
                       '--write-out', '\n%{http_code}']
            result = subprocess.run(command, input=('\n'.join(config) + '\n').encode(),
                                    stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                                    pass_fds=(payload.fileno(),), env=env, timeout=190)
        require(result.returncode == 0, 'HTTPS request failed; remote outcome may be unknown.')
        response, _, code = result.stdout.rpartition(b'\n')
        require(code.isdigit(), 'Invalid HTTP response.')
        if not 200 <= int(code) < 300:
            codes = []
            if api:
                try:
                    for error in json.loads(response).get('errors', [])[:10]:
                        value = error.get('code')
                        if isinstance(value, str) and re.fullmatch(r'[A-Z0-9_.-]{1,80}', value):
                            codes.append(value)
                except (ValueError, AttributeError, TypeError):
                    pass
            suffix = ' (' + ', '.join(codes) + ')' if codes else ''
            raise UploadError('Apple request returned HTTP ' + code.decode() + suffix + '.')
        return response


def b64(value):
    return base64.urlsafe_b64encode(value).rstrip(b'=').decode()


class JWTSigner:
    def __init__(self, path, key_id, issuer=None, individual=False):
        # Do not resolve a symlink first: the submitted path itself must be private.
        require(not path.is_symlink(), 'Private key symlinks are not accepted.')
        real = path.resolve()
        require(ROOT not in real.parents, 'Private key must be outside the repository.')
        require(bool(individual) != bool(issuer), 'Choose individual key or team issuer ID.')
        from cryptography.hazmat.primitives import serialization
        from cryptography.hazmat.primitives.asymmetric import ec
        descriptor = os.open(real, os.O_RDONLY | os.O_NOFOLLOW)
        with os.fdopen(descriptor, 'rb') as stream:
            attrs = os.fstat(stream.fileno())
            require(stat.S_ISREG(attrs.st_mode) and attrs.st_uid == os.getuid() and
                    stat.S_IMODE(attrs.st_mode) == 0o600,
                    'Private key must be owner-only mode 0600.')
            self.key = serialization.load_pem_private_key(stream.read(), password=None)
        require(isinstance(self.key, ec.EllipticCurvePrivateKey) and
                isinstance(self.key.curve, ec.SECP256R1), 'An ES256 App Store Connect key is required.')
        self.key_id, self.issuer, self.individual = identifier(key_id), issuer, individual

    def token(self, method, path):
        from cryptography.hazmat.primitives import hashes
        from cryptography.hazmat.primitives.asymmetric import ec
        from cryptography.hazmat.primitives.asymmetric.utils import decode_dss_signature
        now = int(time.time())
        payload = {'iat': now, 'exp': now + 300, 'aud': 'appstoreconnect-v1'}
        # Scope is optional in Apple's JWT schema. BuildUploads rejected both
        # documented query and path-only GET scope forms during read-only checks.
        # Use the owner-approved Developer key role with a five-minute lifetime;
        # fixed app/file ownership checks below still constrain every mutation.
        payload.update({'sub': 'user'} if self.individual else {'iss': self.issuer})
        header = {'alg': 'ES256', 'kid': self.key_id, 'typ': 'JWT'}
        unsigned = b64(json.dumps(header, separators=(',', ':')).encode()) + '.' + b64(
            json.dumps(payload, separators=(',', ':')).encode())
        r, s = decode_dss_signature(self.key.sign(unsigned.encode(), ec.ECDSA(hashes.SHA256())))
        return unsigned + '.' + b64(r.to_bytes(32, 'big') + s.to_bytes(32, 'big'))


class Client:
    def __init__(self, transport, signer):
        self.transport, self.signer = transport, signer

    def call(self, method, path, body=None):
        require(path.startswith('/v1/'), 'Invalid API path.')
        headers = {'Authorization': 'Bearer ' + self.signer.token(method, path),
                   'Content-Type': 'application/json'}
        raw = self.transport.request(method, API + path, headers,
                                     json.dumps(body).encode() if body is not None else b'', api=True)
        try:
            return json.loads(raw)
        except (ValueError, UnicodeError):
            raise UploadError('Apple returned invalid JSON.') from None


def operations_for_file(operations, size):
    require(isinstance(operations, list) and bool(operations), 'No upload operations returned.')
    ordered = sorted(operations, key=lambda value: value.get('offset', -1))
    cursor = 0
    for operation in ordered:
        offset, length = operation.get('offset'), operation.get('length')
        require(type(offset) is int and type(length) is int and offset == cursor and length > 0,
                'Upload ranges overlap, have a gap, or are invalid.')
        cursor += length
        require(cursor <= size and operation.get('method') == 'PUT', 'Invalid upload range or method.')
        validate_url(operation.get('url'))
        headers = operation.get('requestHeaders', [])
        require(isinstance(headers, list), 'Invalid upload headers.')
        for header in headers:
            require(isinstance(header, dict) and isinstance(header.get('name'), str) and
                    isinstance(header.get('value'), str), 'Invalid upload header.')
    require(cursor == size, 'Upload operations do not cover the entire IPA.')
    return ordered


class Journal:
    def __init__(self, path):
        self.path = path
        identity = {'app_id': APP_ID, 'team_id': TEAM, 'bundle_id': BUNDLE,
                    'version': VERSION, 'build_number': BUILD, 'ipa_sha256': SHA256,
                    'environment': 'staging', 'internal_only': INTERNAL_ONLY}
        if path.exists():
            require(not path.is_symlink(), 'State file symlinks are not accepted.')
            self.data = json.loads(path.read_text())
            require(all(self.data.get(key) == value for key, value in identity.items()),
                    'State belongs to a different candidate.')
            require(set(self.data) <= set(identity) | {
                'phase', 'upload_id', 'file_id', 'updated_at_unix', 'apple_upload_state',
                'build_id', 'build_audience', 'processing_state', 'app_store_uploaded',
                'encryption_attestation_unchanged', 'app_review_submitted', 'publicly_released'},
                'Unexpected fields in upload state; reconcile manually.')
            for key in ('upload_id', 'file_id', 'build_id'):
                if key in self.data:
                    identifier(self.data[key])
        else:
            self.data = {**identity, 'phase': 'new'}

    def save(self, **changes):
        self.data.update(changes)
        self.data['updated_at_unix'] = int(time.time())
        fd, temp = tempfile.mkstemp(prefix='.asc-state-', dir=self.path.parent)
        try:
            with os.fdopen(fd, 'w') as stream:
                json.dump(self.data, stream, indent=2)
                stream.write('\n')
                stream.flush()
                os.fsync(stream.fileno())
            os.replace(temp, self.path)
        finally:
            if os.path.exists(temp):
                os.unlink(temp)


def query_path(path, **values):
    return path + '?' + urlencode(values)


def check_remote(client, journal):
    app = client.call('GET', '/v1/apps/' + APP_ID)['data']
    require(app.get('attributes', {}).get('bundleId') == BUNDLE, 'Remote app bundle mismatch.')
    builds = client.call('GET', query_path('/v1/builds', **{
        'filter[app]': APP_ID, 'filter[version]': BUILD,
        'filter[preReleaseVersion.version]': VERSION,
        'filter[preReleaseVersion.platform]': 'IOS', 'limit': 200}))
    require(not builds.get('links', {}).get('next'), 'Unexpected build pagination; reconcile manually.')
    if builds.get('data'):
        require(journal.data.get('upload_id'), 'Build already exists; no duplicate upload is allowed.')
    uploads = client.call('GET', query_path('/v1/apps/' + APP_ID + '/buildUploads', **{
        'filter[cfBundleVersion]': BUILD, 'filter[cfBundleShortVersionString]': VERSION,
        'filter[platform]': 'IOS', 'limit': 200}))
    require(not uploads.get('links', {}).get('next'), 'Unexpected upload pagination; reconcile manually.')
    for item in uploads.get('data', []):
        require(item.get('id') == journal.data.get('upload_id'),
                'A build upload already exists; no duplicate reservation is allowed.')
    if journal.data.get('upload_id'):
        require(any(item.get('id') == journal.data['upload_id'] for item in uploads.get('data', [])),
                'Saved upload is not bound to this app and version; no writes are allowed.')


def run_upload(client, transport, journal, raw, file_name, poll_seconds=900, sleep=time.sleep):
    require(len(raw) == IPA_SIZE and hashlib.sha256(raw).hexdigest() == SHA256,
            'Upload bytes differ from the fixed candidate.')
    check_remote(client, journal)
    phase = journal.data['phase']
    if not journal.data.get('upload_id'):
        require(phase == 'new', 'Prior upload creation outcome unknown; reconcile before retry.')
        journal.save(phase='creating_upload')
        created = client.call('POST', '/v1/buildUploads', create_upload_body())['data']
        journal.save(upload_id=identifier(created['id']), phase='upload_reserved')
    upload_id = identifier(journal.data['upload_id'])
    if not journal.data.get('file_id'):
        require(journal.data['phase'] == 'upload_reserved',
                'Prior file reservation outcome unknown; reconcile before retry.')
        journal.save(phase='reserving_file')
        created = client.call('POST', '/v1/buildUploadFiles', reserve_file_body(upload_id, file_name))['data']
        journal.save(file_id=identifier(created['id']), phase='file_reserved')
    file_id = identifier(journal.data['file_id'])
    files = client.call('GET', '/v1/buildUploads/' + upload_id + '/buildUploadFiles?limit=200')
    require(not files.get('links', {}).get('next'), 'Unexpected file pagination; reconcile manually.')
    require(any(item.get('id') == file_id for item in files.get('data', [])),
            'Saved file is not bound to this upload; no file writes are allowed.')
    resource = client.call('GET', '/v1/buildUploadFiles/' + file_id)['data']
    attributes = resource.get('attributes', {})
    require(attributes.get('fileSize') == len(raw) and attributes.get('assetType') == 'ASSET',
            'Reserved file metadata mismatch.')
    delivery_state = attributes.get('assetDeliveryState', {}).get('state')
    require(delivery_state != 'FAILED', 'Apple rejected the uploaded file; inspect App Store Connect.')
    if delivery_state not in ('UPLOAD_COMPLETE', 'COMPLETE') and journal.data['phase'] != 'file_committed':
        require(journal.data['phase'] != 'committing_file',
                'Commit outcome unknown; wait for Apple or reconcile before retry.')
        operations = operations_for_file(attributes.get('uploadOperations'), len(raw))
        journal.save(phase='transferring')
        for operation in operations:
            start, length = operation['offset'], operation['length']
            headers = {h['name']: h['value'] for h in operation.get('requestHeaders', [])}
            transport.request('PUT', operation['url'], headers, raw[start:start + length], api=False)
        journal.save(phase='committing_file')
        client.call('PATCH', '/v1/buildUploadFiles/' + file_id, commit_file_body(file_id))
        journal.save(phase='file_committed')
    deadline = time.monotonic() + poll_seconds
    while True:
        upload = client.call('GET', '/v1/buildUploads/' + upload_id + '?include=build')['data']
        upload_attributes = upload.get('attributes', {})
        require(upload_attributes.get('cfBundleShortVersionString') == VERSION and
                upload_attributes.get('cfBundleVersion') == BUILD and
                upload_attributes.get('platform') == 'IOS', 'Remote upload identity mismatch.')
        state = upload.get('attributes', {}).get('state', {}).get('state')
        require(state in ('AWAITING_UPLOAD', 'PROCESSING', 'FAILED', 'COMPLETE'),
                'Unknown Apple upload state; reconcile before retry.')
        require(state != 'FAILED', 'Apple build processing failed; inspect App Store Connect.')
        journal.save(apple_upload_state=state)
        linked = upload.get('relationships', {}).get('build', {}).get('data')
        if state == 'COMPLETE' and linked:
            build_id = identifier(linked['id'])
            response = client.call('GET', '/v1/builds/' + build_id + '?include=app,preReleaseVersion')
            build_resource = response['data']
            build = build_resource['attributes']
            relationships = build_resource.get('relationships', {})
            app_id = relationships.get('app', {}).get('data', {}).get('id')
            pre_id = relationships.get('preReleaseVersion', {}).get('data', {}).get('id')
            pre = next((item.get('attributes', {}) for item in response.get('included', [])
                        if item.get('type') == 'preReleaseVersions' and item.get('id') == pre_id), {})
            require(app_id == APP_ID and pre.get('version') == VERSION and pre.get('platform') == 'IOS',
                    'Processed build belongs to a different app, version, or platform.')
            require(build.get('version') == BUILD, 'Server build number does not match the candidate.')
            processing = build.get('processingState')
            require(processing not in ('FAILED', 'INVALID'),
                    'Apple rejected the processed build; inspect App Store Connect.')
            if processing == 'VALID':
                require(build.get('buildAudienceType') == EXPECTED_AUDIENCE,
                        'Server build audience does not match the selected candidate.')
                journal.save(phase='complete', build_id=build_id, build_audience=EXPECTED_AUDIENCE,
                             processing_state='VALID', app_store_uploaded=True,
                             encryption_attestation_unchanged=True, app_review_submitted=False,
                             publicly_released=False)
                return journal.data
        if time.monotonic() >= deadline:
            journal.save(phase='file_committed')
            raise UploadError('Upload is awaiting processing; rerun with the same state file to poll.')
        sleep(10)


@contextlib.contextmanager
def exclusive_state(path):
    path.parent.mkdir(parents=True, exist_ok=True)
    lock = path.with_suffix(path.suffix + '.lock')
    descriptor = os.open(lock, os.O_RDWR | os.O_CREAT | os.O_NOFOLLOW, 0o600)
    try:
        try:
            fcntl.flock(descriptor, fcntl.LOCK_EX | fcntl.LOCK_NB)
        except BlockingIOError:
            raise UploadError('Another upload process holds this state lock.') from None
        yield
    finally:
        os.close(descriptor)


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--candidate', choices=PROFILES, default='internal-staging-1',
                        help='Fixed verified candidate; build1 internal-only remains the default.')
    parser.add_argument('--upload', action='store_true', help='Explicitly enable Apple API writes.')
    parser.add_argument('--key', type=Path, help='Existing owner-approved App Store Connect .p8 outside Git, mode 0600.')
    parser.add_argument('--key-id')
    group = parser.add_mutually_exclusive_group()
    group.add_argument('--issuer')
    group.add_argument('--individual', action='store_true')
    parser.add_argument('--poll-seconds', type=int, default=900)
    args = parser.parse_args(argv)
    try:
        with candidate_profile(args.candidate):
            raw = validate_artifact(DEFAULT_IPA)
            if not args.upload:
                print(json.dumps({'offline_validated': True, 'candidate_profile': args.candidate,
                                  'ipa_sha256': SHA256, 'internal_only': INTERNAL_ONLY,
                                  'expected_build_audience': EXPECTED_AUDIENCE, 'app_id': APP_ID,
                                  'proposed_create_request': create_upload_body()}, indent=2))
                return 0
            require(args.key is not None and args.key_id and (args.issuer or args.individual),
                    'Upload requires an explicitly supplied existing API key and key type.')
            require(0 <= args.poll_seconds <= 3600, 'Poll duration must be 0..3600 seconds.')
            with exclusive_state(DEFAULT_STATE):
                journal = Journal(DEFAULT_STATE)
                signer = JWTSigner(args.key, args.key_id, args.issuer, args.individual)
                transport = CurlTransport()
                result = run_upload(Client(transport, signer), transport, journal, raw,
                                    DEFAULT_IPA.name, args.poll_seconds)
                print(json.dumps(result, indent=2))
        return 0
    except UploadError as error:
        print('Stopped: ' + str(error))
        return 1
    except Exception:
        print('Stopped safely after an unexpected error. No response payload or credential was logged; preserve the state file.')
        return 1


if __name__ == '__main__':
    raise SystemExit(main())
