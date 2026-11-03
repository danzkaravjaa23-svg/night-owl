import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:sign_in_with_apple/sign_in_with_apple.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../core/constants/app_constants.dart';
import '../../../core/utils/auth_callback.dart';
import 'account_metadata_service.dart';
import 'apple_web_sdk.dart';

class AppleDeletionChallenge {
  final String nonce, clientId;
  final Uri? redirectUri;
  final bool web;
  const AppleDeletionChallenge(
      {required this.nonce,
      required this.clientId,
      required this.web,
      this.redirectUri});
}

class AppleDeletionProof {
  final String authorizationCode, identityToken;
  const AppleDeletionProof(this.authorizationCode, this.identityToken);
}

class AppleDeletionAuthorizationFailure implements Exception {
  final String code;
  const AppleDeletionAuthorizationFailure(this.code);
}

typedef AppleDeletionCredentialRequest = Future<AuthorizationCredentialAppleID>
    Function({
  required String nonce,
  WebAuthenticationOptions? webAuthenticationOptions,
});

/// Reauthorize only; never signs in, links identities, or replaces Supabase auth.
Future<AppleDeletionProof> authorizeAppleDeletion(
  AppleDeletionChallenge challenge, {
  AppleDeletionCredentialRequest? request,
  Future<void> Function()? loadWebSdk,
}) async {
  if (!RegExp(r'^[A-Za-z0-9_-]{43}$').hasMatch(challenge.nonce) ||
      challenge.clientId.trim().isEmpty ||
      (challenge.web &&
          (challenge.redirectUri?.scheme != 'https' ||
              challenge.redirectUri!.host.isEmpty ||
              challenge.redirectUri!.userInfo.isNotEmpty))) {
    throw const AppleDeletionAuthorizationFailure(
        'apple_reauthorization_failed');
  }
  try {
    if (challenge.web) {
      await (loadWebSdk ?? ensureAppleWebSdk)();
    } else if (request == null &&
        (!await SignInWithApple.isAvailable() ||
            !const {TargetPlatform.iOS, TargetPlatform.macOS}
                .contains(defaultTargetPlatform))) {
      throw const AppleDeletionAuthorizationFailure(
          'apple_identity_unavailable');
    }
    final hashed = sha256.convert(utf8.encode(challenge.nonce)).toString();
    final options = challenge.web
        ? WebAuthenticationOptions(
            clientId: challenge.clientId, redirectUri: challenge.redirectUri!)
        : null;
    final credential = await (request ??
                (
                        {required String nonce,
                        WebAuthenticationOptions? webAuthenticationOptions}) =>
                    SignInWithApple.getAppleIDCredential(
                        scopes: const [],
                        nonce: nonce,
                        webAuthenticationOptions: webAuthenticationOptions))(
            nonce: hashed, webAuthenticationOptions: options)
        .timeout(const Duration(minutes: 3));
    final token = credential.identityToken;
    if (credential.authorizationCode.isEmpty ||
        token == null ||
        token.isEmpty) {
      throw const AppleDeletionAuthorizationFailure(
          'apple_reauthorization_failed');
    }
    return AppleDeletionProof(credential.authorizationCode, token);
  } on AppleDeletionAuthorizationFailure {
    rethrow;
  } on SignInWithAppleAuthorizationException catch (error) {
    throw AppleDeletionAuthorizationFailure(
        error.code == AuthorizationErrorCode.canceled
            ? 'apple_cancelled'
            : 'apple_reauthorization_failed');
  } catch (_) {
    // The web plugin reports popup cancellation as a generic credentials error.
    // It is still a failed reauthorization, and cannot reach the deletion phase.
    throw const AppleDeletionAuthorizationFailure(
        'apple_reauthorization_failed');
  }
}

class AppleSignInFailure implements Exception {
  final String message;
  const AppleSignInFailure(this.message);
}

/// Public provider status contains no signing keys or user credentials.
/// Check it before leaving the app, so an unconfigured provider does not
/// navigate the user to a raw server error page.
Future<void> requireAppleProvider({http.Client? client}) async {
  final connection = client ?? http.Client();
  try {
    final response = await connection.get(
      Uri.parse('${AppConstants.supabaseUrl}/auth/v1/settings'),
      headers: {'apikey': AppConstants.supabaseAnonKey},
    ).timeout(const Duration(seconds: 12));
    if (response.statusCode != 200) {
      throw const AppleSignInFailure(
          'Нэвтрэлтийг шалгаж чадсангүй. Дахин оролдоно уу.');
    }
    final settings = jsonDecode(response.body);
    final external = settings is Map ? settings['external'] : null;
    if (external is! Map || external['apple'] is! bool) {
      throw const AppleSignInFailure(
          'Нэвтрэлтийг шалгаж чадсангүй. Дахин оролдоно уу.');
    }
    if (external['apple'] != true) {
      throw const AppleSignInFailure(
          'Apple нэвтрэлт одоогоор идэвхгүй байна. Google эсвэл имэйлээр нэвтэрнэ үү.');
    }
  } on AppleSignInFailure {
    rethrow;
  } catch (_) {
    throw const AppleSignInFailure('Сүлжээгээ шалгаад дахин оролдоно уу.');
  } finally {
    if (client == null) connection.close();
  }
}

Future<void> signInWithApple() async {
  await requireAppleProvider();
  final auth = Supabase.instance.client.auth;
  if (!kIsWeb && defaultTargetPlatform == TargetPlatform.iOS) {
    if (!await SignInWithApple.isAvailable()) {
      throw const AppleSignInFailure(
          'Энэ төхөөрөмж Apple нэвтрэлтийг дэмжихгүй байна.');
    }
    final rawNonce = auth.generateRawNonce();
    final hashedNonce = sha256.convert(utf8.encode(rawNonce)).toString();
    AuthorizationCredentialAppleID credential;
    try {
      credential = await SignInWithApple.getAppleIDCredential(
        scopes: [
          AppleIDAuthorizationScopes.email,
          AppleIDAuthorizationScopes.fullName
        ],
        nonce: hashedNonce,
      );
    } on SignInWithAppleAuthorizationException catch (error) {
      if (error.code == AuthorizationErrorCode.canceled) return;
      throw const AppleSignInFailure(
          'Apple-ээр нэвтэрч чадсангүй. Дахин оролдоно уу.');
    }
    final token = credential.identityToken;
    if (token == null || token.isEmpty) {
      throw const AppleSignInFailure(
          'Apple-ээс нэвтрэх баталгаа ирсэнгүй. Дахин оролдоно уу.');
    }
    final response = await auth.signInWithIdToken(
      provider: OAuthProvider.apple,
      idToken: token,
      nonce: rawNonce,
    );
    if (response.session == null || response.user == null) {
      throw const AppleSignInFailure(
          'Нэвтрэлт баталгаажаагүй байна. Дахин оролдоно уу.');
    }
    // Apple provides a name only on first authorization. Keep it for setup,
    // without replacing a name the user already entered on an earlier login.
    final name = [credential.givenName, credential.familyName]
        .whereType<String>()
        .map((s) => s.trim())
        .where((s) => s.isNotEmpty)
        .join(' ');
    final existing =
        response.user?.userMetadata?['full_name']?.toString().trim() ?? '';
    final ownerId = response.user!.id;
    if (name.isNotEmpty &&
        existing.isEmpty &&
        auth.currentUser?.id == ownerId) {
      try {
        await AccountMetadataService()
            .update({'full_name': name}, ownerId: ownerId);
      } catch (_) {
        // Identity is already verified; name can still be entered in setup.
        debugPrint('Apple profile name could not be saved');
      }
    }
    return;
  }
  final opened = await auth.signInWithOAuth(
    OAuthProvider.apple,
    redirectTo: oauthRedirectUrl(isWeb: kIsWeb, baseUri: Uri.base),
    authScreenLaunchMode: LaunchMode.externalApplication,
  );
  if (!opened) {
    throw const AppleSignInFailure(
        'Apple нэвтрэх хуудсыг нээж чадсангүй. Дахин оролдоно уу.');
  }
}
