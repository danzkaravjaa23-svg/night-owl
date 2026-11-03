import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/services/supabase_service.dart';

class AccountUserUpdateFailure implements Exception {
  final String code;
  const AccountUserUpdateFailure(this.code);

  String get message => code == 'authentication_required'
      ? 'Нэвтрэх эрх дууссан байна. Дахин нэвтэрнэ үү.'
      : 'Бүртгэлийн мэдээллийг хадгалж чадсангүй. Дахин оролдоно уу.';

  @override
  String toString() => message;
}

/// Updates attributes for the captured account without letting a late response
/// replace another login's user. GoTrue 2.20's updateUser copies its response
/// onto whichever session is current after the HTTP request completes.
class AccountUserUpdater {
  final SupabaseClient? _client;
  final http.Client? _httpClient;
  final Duration _requestTimeout;

  AccountUserUpdater({
    SupabaseClient? client,
    http.Client? httpClient,
    Duration requestTimeout = const Duration(seconds: 15),
  })  : _client = client,
        _httpClient = httpClient,
        _requestTimeout = requestTimeout;

  /// False means the request no longer belongs to the active session. The
  /// server may have updated the original account, but local auth is untouched.
  Future<bool> update(Map<String, dynamic> attributes,
      {required String ownerId}) async {
    final client = _client ?? SupabaseService.client;
    final auth = client.auth;
    final captured = auth.currentSession;
    if (captured == null || captured.user.id != ownerId) return false;

    var allowedSession = captured;
    var firstEvent = true;
    var stale = false;
    final subscription = auth.onAuthStateChange.listen((state) {
      // BehaviorSubject replays its last event to new listeners. Only that
      // exact captured Session can be ignored; a fresh login of the same user
      // has a different Session identity and must invalidate this request.
      if (firstEvent && identical(state.session, captured)) {
        firstEvent = false;
        return;
      }
      firstEvent = false;
      if (state.event == AuthChangeEvent.tokenRefreshed &&
          state.session?.user.id == ownerId) {
        allowedSession = state.session!;
      } else {
        stale = true;
      }
    }, onError: (Object _) {
      stale = true;
    });
    final connection = _httpClient ?? http.Client();
    bool isCurrent() =>
        !stale &&
        auth.currentSession?.user.id == ownerId &&
        identical(auth.currentSession, allowedSession);
    try {
      final rest = Uri.parse(client.rest.url);
      const suffix = '/rest/v1';
      if (!const {'http', 'https'}.contains(rest.scheme) ||
          rest.host.isEmpty ||
          rest.userInfo.isNotEmpty ||
          rest.hasQuery ||
          rest.hasFragment ||
          !rest.path.endsWith(suffix)) {
        throw const AccountUserUpdateFailure('configuration');
      }
      final endpoint = rest.replace(
          path: '${rest.path.substring(0, rest.path.length - suffix.length)}'
              '/auth/v1/user');
      final headers = Map<String, String>.from(auth.headers)
        ..removeWhere((key, _) =>
            key.toLowerCase() == 'authorization' ||
            key.toLowerCase() == 'content-type')
        ..addAll({
          'Authorization': 'Bearer ${captured.accessToken}',
          'Content-Type': 'application/json',
        });
      final response = await connection
          .put(endpoint, headers: headers, body: jsonEncode(attributes))
          .timeout(_requestTimeout);
      if (!isCurrent()) return false;
      if (response.statusCode == 401 || response.statusCode == 403) {
        throw const AccountUserUpdateFailure('authentication_required');
      }
      if (response.statusCode != 200) {
        String? code;
        try {
          final error = jsonDecode(response.body);
          if (error is Map) {
            code = (error['code'] ?? error['error_code']) as String?;
          }
        } catch (_) {}
        if (const {
          'weak_password',
          'same_password',
          'reauthentication_needed',
          'reauthentication_not_valid',
        }.contains(code)) {
          throw AccountUserUpdateFailure(code!);
        }
        throw const AccountUserUpdateFailure('request_failed');
      }
      final decoded = jsonDecode(response.body);
      if (decoded is! Map<String, dynamic> ||
          decoded['id'] != ownerId ||
          decoded['user_metadata'] is! Map<String, dynamic>) {
        throw const AccountUserUpdateFailure('invalid_response');
      }
      final user = User.fromJson(decoded);
      if (user == null || user.id != ownerId) {
        throw const AccountUserUpdateFailure('invalid_response');
      }
      // No await between the final guard and setInitialSession: that public
      // SDK method assigns its session synchronously, then emits initialSession.
      // SupabaseFlutter persists every non-null session event. Use the latest
      // allowed session so an intervening refresh never loses its new tokens.
      if (!isCurrent()) return false;
      final latest = auth.currentSession!;
      await auth
          .setInitialSession(jsonEncode(latest.copyWith(user: user).toJson()));
      return true;
    } on AccountUserUpdateFailure {
      rethrow;
    } catch (_) {
      if (!isCurrent()) return false;
      // Network/JSON errors can include URLs, raw responses or credentials.
      throw const AccountUserUpdateFailure('request_failed');
    } finally {
      await subscription.cancel();
      if (_httpClient == null) connection.close();
    }
  }
}
