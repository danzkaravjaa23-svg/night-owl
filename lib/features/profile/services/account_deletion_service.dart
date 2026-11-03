import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../core/services/supabase_service.dart';

class AccountDeletionFailure implements Exception {
  final String code;
  const AccountDeletionFailure(this.code);

  String get message => switch (code) {
        'session_changed' =>
          'Бүртгэл солигдсон эсвэл нэвтрэх эрх дууссан байна. Дахин нэвтэрнэ үү.',
        'deletion_unavailable' =>
          'Устгах үйлчилгээ одоогоор бэлэн биш. Устгал амжилттай болсон гэж батлаагүй.',
        'confirmation_required' => 'Устгах үйлдлээ дахин баталгаажуулна уу.',
        'apple_revocation_required' =>
          'Apple холболтыг аюулгүй цуцлах тохиргоо бэлэн болоогүй тул устгал эхлээгүй.',
        'deletion_failed' =>
          'Устгалын өмнөх шалгалт амжилтгүй боллоо. Дахин оролдоно уу.',
        'deletion_incomplete' =>
          'Устгал бүрэн дууссаныг батлаагүй. Бүртгэл эсвэл зарим медиа устсан байж болно. Дахин оролдохдоо баталгаажуулна уу.',
        _ =>
          'Серверийн хариуг баталж чадсангүй. Бүртгэл эсвэл зарим медиа устсан байж болно. Нэвтрэх боломжоо шалгаад дахин оролдоно уу.',
      };
}

class AccountDeletionService {
  final SupabaseClient? _client;
  final Duration _requestTimeout;
  final Duration _sessionClearTimeout;
  AccountDeletionService(
      {SupabaseClient? client,
      Duration requestTimeout = const Duration(seconds: 60),
      Duration sessionClearTimeout = const Duration(seconds: 5)})
      : _client = client,
        _requestTimeout = requestTimeout,
        _sessionClearTimeout = sessionClearTimeout;

  Future<void> deleteOwnAccount(String expectedUserId) async {
    final client = _client ?? SupabaseService.client;
    final session = client.auth.currentSession;
    if (session == null || session.user.id != expectedUserId) {
      throw const AccountDeletionFailure('session_changed');
    }
    try {
      final response = await client.functions.invoke('delete-account',
          headers: {'Authorization': 'Bearer ${session.accessToken}'},
          body: {'confirmation': 'DELETE'}).timeout(_requestTimeout);
      final data = response.data;
      if (response.status != 200 ||
          data is! Map ||
          data['ok'] != true ||
          data['user_id'] != expectedUserId) {
        throw const AccountDeletionFailure('unknown');
      }
    } on FunctionException catch (error) {
      if (error.status == 401) {
        throw const AccountDeletionFailure('session_changed');
      }
      final details = error.details;
      final code = details is Map ? details['code'] : null;
      const codes = {
        'deletion_unavailable',
        'confirmation_required',
        'apple_revocation_required',
        'deletion_failed',
        'deletion_incomplete'
      };
      if (code is String && codes.contains(code)) {
        throw AccountDeletionFailure(code);
      }
      if (error.status == 404) {
        throw const AccountDeletionFailure('deletion_unavailable');
      }
      throw const AccountDeletionFailure('unknown');
    } on AccountDeletionFailure {
      rethrow;
    } catch (_) {
      // A timeout does not cancel an irreversible operation on the server.
      throw const AccountDeletionFailure('unknown');
    }
  }

  Future<bool> clearDeletedSession(String expectedUserId) async {
    final client = _client ?? SupabaseService.client;
    if (client.auth.currentUser?.id != expectedUserId) {
      return client.auth.currentUser == null;
    }
    try {
      await client.auth
          .signOut(scope: SignOutScope.local)
          .timeout(_sessionClearTimeout);
    } catch (_) {
      // The SDK clears the local session before attempting server logout. A
      // stalled logout endpoint must not trap the completed deletion screen.
    }
    return client.auth.currentUser?.id != expectedUserId;
  }
}

final accountDeletionServiceProvider =
    Provider((ref) => AccountDeletionService());
