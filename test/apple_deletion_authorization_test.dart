import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sign_in_with_apple/sign_in_with_apple.dart';
import 'package:night_owl_ub/features/auth/services/apple_auth_service.dart';

const _credential = AuthorizationCredentialAppleID(
    authorizationCode: 'fresh-code',
    identityToken: 'identity-proof',
    userIdentifier: 'apple-subject',
    givenName: null,
    familyName: null,
    email: null,
    state: null);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('native reauthorization hashes the server nonce and requests proof only',
      () async {
    final nonce = 'A' * 43;
    final result = await authorizeAppleDeletion(
        AppleDeletionChallenge(
            nonce: nonce, clientId: 'com.nightowl.ub.nightOwlUb', web: false),
        request: (
            {required String nonce,
            WebAuthenticationOptions? webAuthenticationOptions}) async {
      expect(nonce, sha256.convert(utf8.encode('A' * 43)).toString());
      expect(webAuthenticationOptions, isNull);
      return _credential;
    });
    expect(result.authorizationCode, 'fresh-code');
    expect(result.identityToken, 'identity-proof');
    // No Supabase singleton was initialized: this path cannot sign in/link.
  });
  test(
      'web loads the SDK only on request and uses the configured Services ID/redirect',
      () async {
    var loaded = false;
    final result = await authorizeAppleDeletion(
        AppleDeletionChallenge(
            nonce: 'B' * 43,
            clientId: 'com.nightowl.web',
            web: true,
            redirectUri: Uri.parse('https://app.test/apple-return')),
        loadWebSdk: () async {
      loaded = true;
    }, request: (
            {required String nonce,
            WebAuthenticationOptions? webAuthenticationOptions}) async {
      expect(loaded, isTrue);
      expect(webAuthenticationOptions?.clientId, 'com.nightowl.web');
      expect(webAuthenticationOptions?.redirectUri.toString(),
          'https://app.test/apple-return');
      expect(nonce, sha256.convert(utf8.encode('B' * 43)).toString());
      return _credential;
    });
    expect(result.identityToken, 'identity-proof');
  });
  test(
      'cancellation produces no proof and remains distinguishable from an erase failure',
      () async {
    await expectLater(
        authorizeAppleDeletion(
            AppleDeletionChallenge(
                nonce: 'A' * 43, clientId: 'native.bundle', web: false),
            request: (
                    {required String nonce,
                    WebAuthenticationOptions?
                        webAuthenticationOptions}) async =>
                throw const SignInWithAppleAuthorizationException(
                    code: AuthorizationErrorCode.canceled,
                    message: 'cancelled')),
        throwsA(isA<AppleDeletionAuthorizationFailure>()
            .having((e) => e.code, 'code', 'apple_cancelled')));
  });
  test('invalid nonce and unsafe web redirects never request credentials',
      () async {
    var requests = 0;
    for (final challenge in [
      const AppleDeletionChallenge(
          nonce: 'bad', clientId: 'native.bundle', web: false),
      AppleDeletionChallenge(
          nonce: 'A' * 43,
          clientId: 'web.id',
          web: true,
          redirectUri: Uri.parse('http://app.test/return')),
      AppleDeletionChallenge(
          nonce: 'A' * 43,
          clientId: 'web.id',
          web: true,
          redirectUri: Uri.parse('https://user:secret@app.test/return')),
    ]) {
      await expectLater(
          authorizeAppleDeletion(challenge, loadWebSdk: () async {}, request: (
              {required String nonce,
              WebAuthenticationOptions? webAuthenticationOptions}) async {
            requests++;
            return _credential;
          }),
          throwsA(isA<AppleDeletionAuthorizationFailure>()));
    }
    expect(requests, 0);
  });
  test('missing Apple identity token cannot reach deletion', () async {
    await expectLater(
        authorizeAppleDeletion(
            AppleDeletionChallenge(
                nonce: 'A' * 43, clientId: 'native.bundle', web: false),
            request: (
                    {required String nonce,
                    WebAuthenticationOptions?
                        webAuthenticationOptions}) async =>
                const AuthorizationCredentialAppleID(
                    authorizationCode: 'code',
                    identityToken: null,
                    userIdentifier: null,
                    givenName: null,
                    familyName: null,
                    email: null,
                    state: null)),
        throwsA(isA<AppleDeletionAuthorizationFailure>()));
  });
  test('SDK load failure is sanitized and never requests Apple credentials',
      () async {
    var requested = false;
    await expectLater(
        authorizeAppleDeletion(
            AppleDeletionChallenge(
                nonce: 'A' * 43,
                clientId: 'web.id',
                web: true,
                redirectUri: Uri.parse('https://app.test/return')),
            loadWebSdk: () async => throw StateError('private-config'),
            request: (
                {required String nonce,
                WebAuthenticationOptions? webAuthenticationOptions}) async {
              requested = true;
              return _credential;
            }),
        throwsA(isA<AppleDeletionAuthorizationFailure>()));
    expect(requested, isFalse);
  });
}
