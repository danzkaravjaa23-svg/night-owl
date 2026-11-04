#!/usr/bin/env python3
"""One-use local entry of existing credentials for the pinned free staging project.

Offline plan by default; only --execute starts a loopback input window. This
helper never contacts Supabase, reads existing credentials, or performs an install or creates accounts.
JWT claims are checked locally; the signature is NOT cryptographically verified.
Run --self-test for synthetic tempfile/in-memory checks without opening sockets.
"""
import argparse
import base64
from datetime import datetime, timezone
from email.message import Message
import hmac
from http.server import BaseHTTPRequestHandler, HTTPServer
import io
import json
import os
from pathlib import Path
import re
import secrets
import stat
import sys
import tempfile
import time
from types import SimpleNamespace
from urllib.parse import parse_qs, urlencode

# Import the same reviewed path/writing guards as the existing password window.
sys.dont_write_bytecode = True
REPO = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(REPO / 'tools' / 'migration'))
import prepare_pgpass
import prepare_source_access

PROJECT_REF = 'sreojqqqhdzkfsrbvlpl'
ORIGIN = f'https://{PROJECT_REF}.supabase.co'
POOLER = 'aws-0-ap-northeast-1.pooler.supabase.com'
DIRECT = f'db.{PROJECT_REF}.supabase.co'
MAX_KEY_LENGTH = 4096
TOKEN_SHAPE = re.compile(r'[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+', re.ASCII)

class InputError(ValueError):
    """Static field/code diagnostics only; never include the submitted value."""
    def __init__(self, field, code):
        self.field, self.code = field, code
        super().__init__('invalid credential field')


def unique_object(pairs):
    result = {}
    for key, value in pairs:
        if key in result:
            raise ValueError('duplicate claim')
        result[key] = value
    return result


def decode_segment(segment):
    decoded = base64.b64decode(segment + '=' * (-len(segment) % 4), altchars=b'-_', validate=True)
    if base64.urlsafe_b64encode(decoded).rstrip(b'=').decode('ascii') != segment:
        raise ValueError('noncanonical JWT')
    return decoded


def validate_key(key, role, field='key'):
    # No trimming: pasted URLs, whitespace, Unicode, colons and backslashes fail.
    if not isinstance(key, str) or not 1 <= len(key) <= MAX_KEY_LENGTH or not TOKEN_SHAPE.fullmatch(key):
        raise InputError(field, 'legacy_format')
    header_segment, payload_segment, signature_segment = key.split('.')
    try:
        header = json.loads(decode_segment(header_segment).decode('utf-8'), object_pairs_hook=unique_object)
        claims = json.loads(decode_segment(payload_segment).decode('utf-8'), object_pairs_hook=unique_object)
        signature = decode_segment(signature_segment)
    except Exception:
        raise InputError(field, 'legacy_format') from None
    if (not isinstance(header, dict) or header.get('alg') != 'HS256' or header.get('typ') != 'JWT'
            or len(signature) != 32 or not isinstance(claims, dict)):
        raise InputError(field, 'legacy_format')
    if claims.get('ref') != PROJECT_REF:
        raise InputError(field, 'wrong_project')
    if claims.get('role') != role:
        raise InputError(field, 'wrong_role')
    # This is a claims/shape check only, never a signature or authorization check.


def output_path(value):
    raw = Path(value).expanduser()
    if (not raw.is_absolute() or '..' in raw.parts or raw.name in ('', '.', '..')
            or any(c in str(raw) for c in '\r\n\0')):
        raise ValueError('unsafe output path')
    return prepare_pgpass.no_symlinks(raw)


def open_safe_parent(path):
    fd = prepare_source_access.open_directory(path.parent)
    meta = os.fstat(fd)
    if meta.st_uid != os.getuid() or meta.st_mode & 0o022:
        os.close(fd)
        raise ValueError('unsafe parent')
    return fd


def require_absent(parent, name):
    try:
        os.stat(name, dir_fd=parent, follow_symlinks=False)
    except FileNotFoundError:
        return
    raise ValueError('output already exists')


def preflight_output(value):
    output = output_path(value)
    parent = open_safe_parent(output)
    try:
        require_absent(parent, output.name)
    finally:
        os.close(parent)
    return output


def validate_fields(fields):
    password = fields['password']
    if (not isinstance(password, str) or not 1 <= len(password) <= 1024
            or any(c in password for c in '\r\n\0') or password.startswith(('postgres://', 'postgresql://'))):
        raise InputError('password', 'password_format')
    validate_key(fields['anon'], 'anon', 'anon')
    validate_key(fields['service'], 'service_role', 'service')


def save_private(args, fields):
    validate_fields(fields)
    output = output_path(args.output)
    ca = output_path(args.ca)
    if not ca.is_file():
        raise ValueError('CA missing')
    parent = open_safe_parent(output)
    child = None
    created_dir = False
    created_files = []
    try:
        os.mkdir(output.name, mode=0o700, dir_fd=parent)
        created_dir = True
        child = os.open(output.name, os.O_RDONLY | os.O_DIRECTORY | os.O_NOFOLLOW, dir_fd=parent)
        os.fchmod(child, 0o700)
        services, passes = [], []
        for alias, host, user in [('nightowl_staging', POOLER, 'postgres.' + PROJECT_REF),
                                  ('nightowl_staging_direct', DIRECT, 'postgres')]:
            services.append(f'[{alias}]\nhost={host}\nport=5432\ndbname=postgres\nuser={user}\nsslmode=verify-full\nsslrootcert={ca}\n')
            passes.append(':'.join(prepare_pgpass.escape(value) for value in
                          (host, '5432', 'postgres', user, fields['password'])))
        auth = {'origin': ORIGIN, 'anon_key': fields['anon'], 'service_role_key': fields['service']}
        for name, content in [('service.conf', '\n'.join(services)), ('pgpass', '\n'.join(passes) + '\n'),
                              ('api.json', json.dumps(auth) + '\n')]:
            prepare_source_access.write_private(child, name, content, created_files)
        os.fsync(child)
        os.fsync(parent)
    except BaseException:
        if child is not None:
            for name in created_files:
                try:
                    os.unlink(name, dir_fd=child)
                except OSError:
                    pass
        if created_dir:
            try:
                os.rmdir(output.name, dir_fd=parent)
            except OSError:
                pass
        raise
    finally:
        fields = None
        if child is not None:
            os.close(child)
        os.close(parent)


class PrivateStatus:
    """New metadata-only file; retain an exclusive descriptor for later updates."""
    def __init__(self, value, output):
        path = output_path(value)
        self.output = str(output)
        parent = open_safe_parent(path)
        try:
            self.fd = os.open(path.name, os.O_WRONLY | os.O_CREAT | os.O_EXCL | os.O_NOFOLLOW, 0o600, dir_fd=parent)
            os.fchmod(self.fd, 0o600)
        finally:
            os.close(parent)

    def write(self, state, rejected_checks=None):
        record = {'state': state, 'at': datetime.now(timezone.utc).isoformat(),
                  'output': self.output, 'remote_accessed': False, 'signature_verified': False}
        if rejected_checks:
            record['rejected_checks'] = rejected_checks
        data = (json.dumps(record) + '\n').encode('utf-8')
        os.lseek(self.fd, 0, os.SEEK_SET)
        written = 0
        while written < len(data):
            count = os.write(self.fd, data[written:])
            if count <= 0:
                raise OSError('status write failed')
            written += count
        os.ftruncate(self.fd, len(data))
        os.fsync(self.fd)

    def close(self):
        os.close(self.fd)


STYLE = '''body{margin:0;background:#0b0d17;color:#f4f1ff;font:16px -apple-system,BlinkMacSystemFont,sans-serif;line-height:1.6;display:grid;min-height:100vh;place-items:center}main{box-sizing:border-box;width:min(580px,92vw);padding:36px;border:1px solid #33304e;border-radius:24px;background:#151525}h1{font-size:27px;line-height:1.3;margin:16px 0}p{color:#c8c2dc}.brand{color:#b6a4ff;font-weight:650}label{display:block;font-weight:600;margin-top:25px}input[type=password]{box-sizing:border-box;width:100%;margin:10px 0 18px;padding:15px;background:#0b0d17;color:white;border:1px solid #8880aa;border-radius:12px;font-size:19px}input:focus{outline:2px solid #b6a4ff}button{width:100%;padding:14px;border:0;border-radius:12px;background:#7654d6;color:white;font-size:17px;font-weight:650;cursor:pointer}.cancel{margin-top:12px;background:transparent;color:#bcb5d0;border:1px solid #393349}.note{font-size:14px;color:#a9a3bd}.ok{color:#a6e4c1}'''


class StagingAccessServer(HTTPServer):
    allow_reuse_address = False

    def __init__(self, args, status):
        super().__init__(('127.0.0.1', 0), StagingAccessHandler)
        self.args = args
        self.private_status = status
        self.expected_host = f'127.0.0.1:{self.server_port}'
        self.origin = f'http://{self.expected_host}'
        self.csrf = secrets.token_urlsafe(32)
        self.done = False
        self.deadline = time.monotonic() + 900
        self.timeout = 1

    def get_request(self):
        connection, address = super().get_request()
        connection.settimeout(5)
        return connection, address

    def handle_error(self, request, client_address):
        pass  # Never print bodies, submitted values or arbitrary exceptions.

    def status(self, state, rejected_checks=None):
        self.private_status.write(state, rejected_checks)


class StagingAccessHandler(BaseHTTPRequestHandler):
    def log_message(self, *args):
        pass

    def send_error(self, code, message=None, explain=None):
        # Base HTTP errors otherwise reflect arbitrary request text.
        self.close_connection = True
        self.page('Хүсэлт буруу байна.', code)

    def allowed_host(self):
        return self.headers.get_all('Host') == [self.server.expected_host]

    def page(self, content, status=200):
        document = ('<!doctype html><html lang="mn"><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>Night Owl — Туршилтын орчны холболт</title><style>' + STYLE + '</style><main>' + content + '</main></html>').encode('utf-8')
        self.send_response(status)
        self.send_header('Content-Type', 'text/html; charset=utf-8')
        self.send_header('Content-Length', str(len(document)))
        self.send_header('Cache-Control', 'no-store')
        # Same-origin keeps the browser's form Origin intact and limits referrers.
        self.send_header('Referrer-Policy', 'same-origin')
        self.send_header('X-Content-Type-Options', 'nosniff')
        self.send_header('Content-Security-Policy', "default-src 'none'; style-src 'unsafe-inline'; form-action 'self'; frame-ancestors 'none'; base-uri 'none'")
        self.end_headers()
        self.wfile.write(document)

    def do_GET(self):
        if not self.allowed_host() or self.path != '/' or self.server.done or time.monotonic() >= self.server.deadline:
            return self.page('Цонх идэвхгүй байна.', 404)
        token = self.server.csrf
        inputs = ''.join('<label for="' + name + '">' + label + '</label><input id="' + name + '" name="' + name + '" type="password" autocomplete="off" autocapitalize="off" spellcheck="false" maxlength="4096" required>'
                         for name, label in [('password', '1. Staging төслийн Database password'),
                                             ('anon', '2. Legacy anon (public) JWT'),
                                             ('service', '3. Legacy service_role (secret) JWT')])
        self.page('<div class="brand">🦉 NIGHT OWL · ҮНЭГҮЙ STAGING</div><h1>Туршилтын орчны холболт</h1><p>Зөвхөн <strong>night-owl-staging</strong> төслийн одоо байгаа нууц үг, түлхүүрийг оруулна. Энд шинэ нууц үг үүсгэхгүй, солихгүй.</p><p class="note">Төслийн ref: <strong>' + PROJECT_REF + '</strong>. Production төслийн түлхүүрийг хүлээн авахгүй.</p><form method="post" action="/save" autocomplete="off"><input type="hidden" name="csrf" value="' + token + '">' + inputs + '<button type="submit">Энэ Mac дээр хувийн файлд хадгалах</button></form><form method="post" action="/cancel"><input type="hidden" name="csrf" value="' + token + '"><button class="cancel" type="submit">Цуцлах</button></form><p class="note">Эдгээр нь зөвхөн энэ Mac-ийн Git-ээс гадуурх хамгаалсан хавтаст хадгалагдана. Дараа нь staging-д хүснэгт суулгаж, тест аккаунтаар нэвтрэлт ба файл шалгахад ашиглана. service_role нь админ эрхтэй тул чатад болон GitHub-д оруулахгүй. Энэ маягт гаднын серверт холбогдохгүй. 15 минут хүчинтэй.</p>')


    def do_POST(self):
        checks = {
            'host': self.allowed_host(),
            'origin': self.headers.get_all('Origin') == [self.server.origin],
            'site': self.headers.get_all('Sec-Fetch-Site', ['same-origin']) == ['same-origin'],
            'active': not self.server.done and time.monotonic() < self.server.deadline,
            'path': self.path in ('/save', '/cancel'),
            'framing': self.headers.get_all('Transfer-Encoding') is None and len(self.headers.get_all('Content-Length', [])) == 1,
            'type': self.headers.get_all('Content-Type') == ['application/x-www-form-urlencoded'],
        }
        if not all(checks.values()):
            self.server.status('waiting' if checks['active'] else 'inactive', [name for name, valid in checks.items() if not valid])
            return self.page('Хүсэлтийг зөвшөөрсөнгүй.', 403)
        fields = None
        try:
            size = int(self.headers['Content-Length'])
            if not 0 < size <= 16384:
                raise ValueError('body size')
            body = self.rfile.read(size)
            if len(body) != size:
                raise ValueError('incomplete body')
            fields = parse_qs(body.decode('utf-8'), keep_blank_values=True, strict_parsing=True, max_num_fields=4)
            body = None
            if fields.keys() != ({'csrf', 'password', 'anon', 'service'} if self.path == '/save' else {'csrf'}):
                raise ValueError('fields')
            if any(len(v) != 1 for v in fields.values()) or not hmac.compare_digest(fields['csrf'][0], self.server.csrf):
                raise ValueError('csrf')
            if self.server.done or time.monotonic() >= self.server.deadline:
                raise ValueError('expired')
        except Exception:
            fields = None
            return self.page('Хүсэлт буруу байна. Цонхыг дахин нээгээрэй.', 400)
        if self.path == '/cancel':
            fields = None
            self.server.done = True
            self.server.status('cancelled')
            return self.page('<h1>Цуцаллаа</h1><p>Түлхүүр хадгалаагүй.</p>')
        try:
            save_private(self.server.args, {name: fields[name][0] for name in ('password', 'anon', 'service')})
        except InputError as error:
            names = {'password': 'Database password', 'anon': 'anon түлхүүр', 'service': 'service_role түлхүүр'}
            messages = {
                'legacy_format': 'Legacy API Keys хэсгийн eyJ гэж эхэлдэг JWT хэрэгтэй. sb_publishable / sb_secret түлхүүр болон URL энэ маягтад тохирохгүй.',
                'wrong_project': 'Энэ түлхүүр night-owl-staging төслийнх биш байна. Шинэ staging төслийн API Keys хэсгээс хуулна уу.',
                'wrong_role': 'Хоёр түлхүүрийн байрлал солигдсон байж болно. Талбарын нэртэй ижил түлхүүрийг хуулна уу.',
                'password_format': 'Төсөл үүсгэхдээ оруулсан Database password-оо нэг мөрөөр оруулна уу. Connection URL оруулахгүй.',
            }
            self.server.status('waiting', [error.field + '_' + error.code])
            return self.page('<h1>' + names[error.field] + ' шалгалтад тохирсонгүй</h1><p>' + messages[error.code] + '</p><p>Юу ч хадгалаагүй. Нууц утгуудыг чатад бүү оруулаарай.</p><p><a style="color:#b6a4ff" href="/">Маягтаа дахин нээх</a></p>', 400)
        except Exception:
            self.server.done = True
            self.server.status('failed')
            return self.page('<h1>Хадгалж чадсангүй</h1><p>Нууц утгуудаа чатад илгээхгүйгээр Codex-д мэдэгдээрэй. Түлхүүрүүд нь заасан staging төслийн legacy anon болон service_role JWT байх ёстой.</p>', 400)
        finally:
            fields = None
        self.server.done = True
        self.server.status('saved')
        self.page('<div class="brand">🦉 NIGHT OWL</div><h1 class="ok">Хадгаллаа</h1><p>Одоо Codex чатад <strong>«staging холболтоо орууллаа»</strong> гэж бичээрэй. Түлхүүрийн утгыг чатад бүү оруулаарай.</p><p class="note">Түлхүүр энэ Mac дээр хадгалагдсан. Staging-д хараахан холбогдоогүй, суулгалт эхлээгүй. Энэ цонхыг хааж болно.</p>')


def self_test():
    """Fabricated credentials only, no sockets or external connections."""
    checks = []
    def check(name, ok):
        if not ok:
            raise RuntimeError('synthetic check failed')
        checks.append(name)
    def rejected(fn):
        try:
            fn()
        except Exception:
            return True
        return False
    def segment(value):
        return base64.urlsafe_b64encode(json.dumps(value).encode()).rstrip(b'=').decode()
    def fake(role, ref=PROJECT_REF):
        return '.'.join([segment({'alg':'HS256','typ':'JWT'}), segment({'role':role,'ref':ref}),
                         base64.urlsafe_b64encode(b'0'*32).rstrip(b'=').decode()])
    values = {'password': r'synthetic:password\special', 'anon': fake('anon'), 'service': fake('service_role')}
    validate_fields(values)
    check('correct_fields', True)
    for name, invalid in [('wrong_project', {**values, 'service':fake('service_role','jbbdnpsvstwxtgtjoeru')}),
                          ('wrong_role', {**values, 'anon':fake('service_role')}),
                          ('password_line', {**values, 'password':'bad\nvalue'}),
                          ('password_url', {**values, 'password':'postgresql://bad'}),
                          ('key_newline', {**values, 'anon':values['anon']+'\n'})]:
        check(name, rejected(lambda: validate_fields(invalid)))
    with tempfile.TemporaryDirectory(prefix='nightowl-staging-input-') as temporary:
        root = Path(temporary).resolve()
        root.chmod(0o700)
        ca = root / 'synthetic-ca.crt'
        ca.write_text('SYNTHETIC PUBLIC CA FIXTURE')
        target = root / 'access'
        args = SimpleNamespace(output=target, ca=ca)
        save_private(args, values)
        check('directory_700', stat.S_IMODE(target.stat().st_mode) == 0o700)
        check('files_600', all(stat.S_IMODE(p.stat().st_mode)==0o600 for p in target.iterdir()))
        check('api_pin', json.loads((target/'api.json').read_text()) == {'origin':ORIGIN, 'anon_key':values['anon'], 'service_role_key':values['service']})
        entries = prepare_pgpass.parse_passfile((target/'pgpass').read_text())
        check('password_roundtrip', len(entries)==2 and all(e[4]==values['password'] for e in entries))
        check('tls_verify_full', (target/'service.conf').read_text().count('sslmode=verify-full')==2)
        check('no_overwrite', rejected(lambda: save_private(args, values)))
        (root/'link').symlink_to(target, target_is_directory=True)
        check('symlink_rejected', rejected(lambda: output_path(root/'link')))
        check('git_path_rejected', rejected(lambda: output_path(REPO/'build'/'credential-fixture')))
        records = []
        server = SimpleNamespace(args=SimpleNamespace(output=root/'request-access', ca=ca),
            expected_host='127.0.0.1:43127', origin='http://127.0.0.1:43127', csrf='synthetic-csrf', done=False,
            deadline=time.monotonic()+900, status=lambda *record: records.append(record))
        def request(origin=None, csrf=None, extra=None, method='POST'):
            handler = StagingAccessHandler.__new__(StagingAccessHandler)
            handler.server=server
            handler.path='/' if method=='GET' else '/save'
            handler.command=method
            handler.request_version='HTTP/1.1'
            handler.requestline=method+' '+handler.path+' HTTP/1.1'
            handler.headers=Message()
            handler.headers['Host']=server.expected_host
            handler.headers['Origin']=server.origin if origin is None else origin
            handler.headers['Sec-Fetch-Site']='same-origin'
            handler.headers['Content-Type']='application/x-www-form-urlencoded'
            body=urlencode({'csrf':server.csrf if csrf is None else csrf, **values}).encode()+(extra or b'')
            handler.headers['Content-Length']=str(len(body))
            handler.rfile=io.BytesIO(body)
            handler.wfile=io.BytesIO()
            getattr(handler,'do_'+method)()
            response=handler.wfile.getvalue()
            check('no_secret_echo', not any(v.encode() in response for v in values.values()))
            return response
        check('cross_origin_rejected', b' 403 ' in request(origin='https://example.invalid'))
        check('csrf_rejected', b' 400 ' in request(csrf='wrong'))
        check('duplicate_field_rejected', b' 400 ' in request(extra=b'&password=duplicate'))
        check('no_rejected_save', not server.args.output.exists())
        original_anon = values['anon']
        values['anon'] = fake('anon', 'different-project')
        check('field_error_without_secret', b' 400 ' in request()
              and records[-1] == ('waiting', ['anon_wrong_project']))
        check('invalid_input_can_retry', not server.done and not server.args.output.exists())
        values['anon'] = original_anon
        form=request(method='GET')
        check('three_masked_fields', form.count(b'type="password"')==3)
        check('no_store', b'Cache-Control: no-store' in form)
        server.deadline=time.monotonic()-1
        check('expiry_rejected', b' 403 ' in request())
        server.deadline=time.monotonic()+900
        check('valid_save', b' 200 ' in request() and server.done)
        check('one_use', b' 403 ' in request())
        check('no_metadata_secret', not any(v in json.dumps(records) for v in values.values()))
    print(json.dumps({'state':'self_test_passed','checks':len(checks),'synthetic_only':True,'sockets_opened':False,'checks_passed':checks}))


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--execute', action='store_true', help='Start the one-use local input window only after approval')
    parser.add_argument('--self-test', action='store_true', help='Synthetic offline tests only')
    parser.add_argument('--output', type=Path, help='New absolute private directory outside every Git checkout')
    parser.add_argument('--ca', type=Path, help='Existing public Supabase CA certificate path')
    parser.add_argument('--status', type=Path, help='New metadata-only status file outside every Git checkout')
    args = parser.parse_args()
    if args.self_test:
        if args.execute or args.output or args.status or args.ca:
            parser.error('--self-test must be used alone')
        self_test()
        return
    if not args.execute:
        print(json.dumps({'state': 'offline_plan', 'requires_explicit_execution': True,
                          'project_ref': PROJECT_REF,
                          'remote_accessed': False, 'sockets_opened': False}))
        return
    if not args.output or not args.status or not args.ca:
        parser.error('--execute requires --output, --status and --ca')
    args.output = preflight_output(args.output)
    args.ca = output_path(args.ca)
    if not args.ca.is_file():
        raise ValueError('Public CA certificate missing')
    status_path = output_path(args.status)
    if status_path == args.output or args.output in status_path.parents:
        raise ValueError('status must be separate from key output')
    status = PrivateStatus(status_path, args.output)
    try:
        with StagingAccessServer(args, status) as server:
            server.status('waiting')
            print(json.dumps({'url': server.origin, 'state': 'waiting'}), flush=True)
            while not server.done and time.monotonic() < server.deadline:
                server.handle_request()
            if not server.done:
                server.status('expired')
    finally:
        status.close()


if __name__ == '__main__':
    try:
        main()
    except (KeyboardInterrupt, EOFError):
        print('Private staging input cancelled. No input values printed.', file=sys.stderr)
        sys.exit(2)
    except Exception:
        print('Private staging input could not complete. No input values printed.', file=sys.stderr)
        sys.exit(2)
