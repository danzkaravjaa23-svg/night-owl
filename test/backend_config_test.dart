import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:night_owl_ub/core/config/backend_config.dart';
import 'package:night_owl_ub/core/constants/app_constants.dart';

String jwt(String role) {
  final claims = base64Url
      .encode(utf8.encode(jsonEncode({'role': role, 'aud': 'authenticated'})))
      .replaceAll('=', '');
  return 'eyJhbGciOiJIUzI1NiJ9.$claims.test-signature';
}

void main() {
  BackendConfig parse(String url,
          {String mode = 'postgres', String? key, bool local = false}) =>
      BackendConfig.parse(
          mode: mode,
          url: url,
          publicKey: key ?? jwt('anon'),
          allowLocalHttp: local);

  test('current live backend remains valid while migration is pending', () {
    final config = BackendConfig.parse(
        mode: AppConstants.backendMode,
        url: AppConstants.backendUrl,
        publicKey: AppConstants.backendPublicKey,
        allowLocalHttp: false);
    expect(config.mode, BackendMode.supabase);
    expect(config.url.host, 'jbbdnpsvstwxtgtjoeru.supabase.co');
    expect(config.sessionStorageKey, 'sb-jbbdnpsvstwxtgtjoeru-auth-token');
  });

  test('independent HTTPS origin is shared by every client service', () {
    final config = parse('https://api.nightowl.example/');
    expect(config.mode, BackendMode.postgres);
    expect(config.url.toString(), 'https://api.nightowl.example');
  });

  test('database DSNs, credentials and non-origin URLs are rejected', () {
    for (final url in [
      'postgresql://owner:secret@db.example/database',
      'https://owner:secret@api.example',
      'https://api.example/rest/v1',
      'https://api.example?password=secret',
      'https://api.example#auth',
      '',
    ]) {
      expect(() => parse(url), throwsFormatException);
    }
  });

  test('PostgreSQL mode cannot silently keep the managed backend', () {
    for (final host in [
      'jbbdnpsvstwxtgtjoeru.supabase.co',
      'supabase.co',
      'project.supabase.in',
      'supabase.in'
    ]) {
      expect(() => parse('https://$host'), throwsFormatException);
    }
  });

  test('production never sends credentials over HTTP', () {
    expect(() => parse('http://api.example'), throwsFormatException);
    expect(() => parse('http://127.0.0.1:8080'), throwsFormatException);
    expect(() => parse('http://192.168.1.10:8080', local: true),
        throwsFormatException);
  });

  test('development allows HTTP only on explicit loopback origins', () {
    for (final host in ['localhost', '127.0.0.1', '[::1]']) {
      expect(parse('http://$host:8080', local: true).url.port, 8080);
    }
  });

  test('service and authenticated JWTs cannot be embedded in a build', () {
    for (final role in ['service_role', 'authenticated', 'postgres', 'admin']) {
      expect(() => parse('https://api.example', key: jwt(role)),
          throwsFormatException);
    }
    expect(() => parse('https://api.example', key: 'sb_secret_test'),
        throwsFormatException);
  });

  test('malformed keys and a managed publishable key fail for PostgREST', () {
    for (final key in [
      '',
      'server-secret',
      'a.not-base64.signature',
      'sb_publishable_test'
    ]) {
      expect(
          () => parse('https://api.example', key: key), throwsFormatException);
    }
  });

  test('managed mode accepts its public key format', () {
    expect(
        parse('https://project.supabase.co',
                mode: 'supabase', key: 'sb_publishable_test')
            .mode,
        BackendMode.supabase);
  });

  test('public JWT cannot carry a user identity or wrong API audience', () {
    for (final claims in [
      {'role': 'anon', 'aud': 'wrong'},
      {'role': 'anon'},
      {'role': 'anon', 'aud': 'authenticated', 'sub': 'private-user'},
    ]) {
      final payload = base64Url.encode(utf8.encode(jsonEncode(claims)));
      expect(
          () => parse('https://api.example', key: 'header.$payload.signature'),
          throwsFormatException);
    }
  });

  test('unknown modes fail rather than choosing an unintended backend', () {
    expect(() => parse('https://api.example', mode: 'postgresql'),
        throwsFormatException);
  });

  test('independent sessions cannot cross API hosts or ports', () {
    final production = parse('https://api.nightowl.example');
    final staging = parse('https://api.staging.example');
    final alternatePort = parse('https://api.nightowl.example:8443');
    expect(production.sessionStorageKey, isNot(staging.sessionStorageKey));
    expect(
        production.sessionStorageKey, isNot(alternatePort.sessionStorageKey));
    expect(production.sessionStorageKey,
        parse('https://api.nightowl.example/').sessionStorageKey);
    expect(production.sessionStorageKey, isNot(startsWith('sb-')));
  });
}
