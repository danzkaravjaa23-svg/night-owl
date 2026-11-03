import 'account_deletion_receipt_store.dart';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import '../../auth/services/apple_auth_service.dart';
import '../../post/services/content_publication.dart';
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
        'receipt_storage_unavailable' =>
          'Устгалын сэргээх баталгааг төхөөрөмжид аюулгүй хадгалж чадсангүй. Энэ оролдлогыг үргэлжлүүлээгүй; хадгалах боломжоо шалгаад дахин оролдоно уу.',
        'apple_cancelled' =>
          'Apple баталгаажуулалтыг цуцаллаа. Өмнөх устгах хүсэлттэй бол төлөвийг шалгаарай.',
        'apple_not_configured' =>
          'Apple холболтыг цуцлах серверийн тохиргоо бэлэн биш. Өмнөх устгах хүсэлттэй бол төлөвийг шалгаарай.',
        'apple_identity_unavailable' =>
          'Apple баталгаажуулалт энэ төхөөрөмж дээр боломжгүй байна. Apple холболттой бүртгэлээ iPhone эсвэл web апп дээр устгана уу.',
        'apple_reauthorization_required' ||
        'apple_reauthorization_failed' =>
          'Apple баталгаажуулалт амжилтгүй. Нэвтэрсэн Apple бүртгэлээ шалгаад дахин оролдоно уу.',
        'apple_revocation_failed' =>
          'Apple холболтыг цуцалсныг баталж чадсангүй. Дахин оролдоно уу.',
        'deletion_busy' =>
          'Өмнөх устгах хүсэлт боловсруулагдаж байна. Түр хүлээгээд төлөвийг дахин шалгаарай.',
        'deletion_unavailable' =>
          'Устгах үйлчилгээ одоогоор бэлэн биш. Устгал амжилттай болсон гэж батлаагүй.',
        'confirmation_required' => 'Устгах үйлдлээ дахин баталгаажуулна уу.',
        'apple_revocation_required' =>
          'Apple холболтыг аюулгүй цуцлах тохиргоо бэлэн болоогүй. Өмнөх устгах хүсэлттэй бол төлөвийг шалгаарай.',
        'deletion_failed' =>
          'Устгах хүсэлтийг дуусгаж чадсангүй. Төлөвийг шалгаад дахин оролдоно уу.',
        'deletion_incomplete' =>
          'Устгал бүрэн дууссаныг батлаагүй. Бүртгэл эсвэл зарим медиа устсан байж болно. Дахин оролдохдоо баталгаажуулна уу.',
        _ =>
          'Серверийн хариуг баталж чадсангүй. Бүртгэл эсвэл зарим медиа устсан байж болно. Нэвтрэх боломжоо шалгаад дахин оролдоно уу.',
      };
}

class AccountDeletionService {
  final SupabaseClient? _client;
  final http.Client? _transport;
  final Duration _requestTimeout, _sessionClearTimeout;
  final Future<AppleDeletionProof> Function(AppleDeletionChallenge) _apple;
  final bool _web;
  final AccountDeletionReceiptStore _receiptStore;
  Future<void>? _restoration;
  final _started = <String, DateTime>{};
  // Capability receipts stay in secure storage, never logs, URLs, or Apple proof storage.
  final _receipts = <String, String>{};
  final _completionSessions = <String, Session?>{};
  AccountDeletionService(
      {SupabaseClient? client,
      http.Client? httpClient,
      Future<AppleDeletionProof> Function(AppleDeletionChallenge)?
          appleReauthorize,
      AccountDeletionReceiptStore? receiptStore,
      bool? web,
      Duration requestTimeout = const Duration(seconds: 60),
      Duration sessionClearTimeout = const Duration(seconds: 5)})
      : _client = client,
        _transport = httpClient,
        _apple = appleReauthorize ?? authorizeAppleDeletion,
        _web = web ?? kIsWeb,
        _receiptStore = receiptStore ?? const AccountDeletionReceiptStore(),
        _requestTimeout = requestTimeout,
        _sessionClearTimeout = sessionClearTimeout;
  SupabaseClient get client => _client ?? SupabaseService.client;
  bool hasPendingReceipt(String owner) => _receipts.containsKey(owner);
  String? get pendingOwnerId => _receipts.isEmpty ? null : _receipts.keys.last;

  Future<void> restorePendingReceipts() => _restoration ??= _restore();
  Future<void> _restore() async {
    try {
      final raw = await _receiptStore.read();
      if (raw == null) return;
      if (raw.length > 32768) throw const FormatException();
      final rows = jsonDecode(raw);
      if (rows is! List || rows.length > 8) throw const FormatException();
      final now = DateTime.now().toUtc();
      final parsed = <(String, String, DateTime)>[];
      for (final row in rows) {
        if (row is! Map ||
            row.keys.toSet().difference(
                {'owner_id', 'receipt_token', 'started_at'}).isNotEmpty) {
          continue;
        }
        final owner = row['owner_id'],
            token = row['receipt_token'],
            timestamp = row['started_at'];
        final started =
            timestamp is String ? DateTime.tryParse(timestamp) : null;
        if (owner is! String ||
            !RegExp(r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$')
                .hasMatch(owner) ||
            token is! String ||
            !RegExp(r'^[A-Za-z0-9_-]{43}$').hasMatch(token) ||
            started == null ||
            !started.isUtc ||
            started.isAfter(now.add(const Duration(minutes: 5))) ||
            now.difference(started) >= const Duration(days: 30)) {
          continue;
        }
        parsed.add((owner, token, started));
      }
      parsed.sort((a, b) => a.$3.compareTo(b.$3));
      for (final row in parsed) {
        _receipts[row.$1] = row.$2;
        _started[row.$1] = row.$3;
      }
    } catch (_) {
      _restoration = null;
      throw const AccountDeletionFailure('receipt_storage_unavailable');
    }
  }

  Future<void> _saveReceipts() async {
    try {
      await _receiptStore.write(jsonEncode([
        for (final owner in _receipts.keys)
          {
            'owner_id': owner,
            'receipt_token': _receipts[owner],
            'started_at': _started[owner]!.toUtc().toIso8601String()
          },
      ]));
    } catch (_) {
      throw const AccountDeletionFailure('receipt_storage_unavailable');
    }
  }

  Future<void> _forgetCompleted(String owner) async {
    final receipt = _receipts.remove(owner), started = _started.remove(owner);
    try {
      await _saveReceipts();
    } catch (_) {
      if (receipt != null && started != null) {
        _receipts[owner] = receipt;
        _started[owner] = started;
      }
      // Completion was verified; retaining a status-only capability is safer
      // than pretending account erasure itself failed on local cleanup.
    }
  }

  void _checkOwner(String expected) {
    final current = client.auth.currentUser?.id;
    if (current != null && current != expected) {
      throw const AccountDeletionFailure('session_changed');
    }
  }

  bool _complete(_DeletionReply reply, String expected) =>
      reply.status == 200 &&
      reply.data['ok'] == true &&
      reply.data['user_id'] == expected;

  Future<void> deleteOwnAccount(
    String expectedUserId, {
    Future<AppleDeletionProof> Function(AppleDeletionChallenge)?
        appleReauthorize,
  }) async {
    await restorePendingReceipts();
    _checkOwner(expectedUserId);
    final prior = _receipts[expectedUserId];
    if (prior != null) {
      // A deliberate retry first checks the same operation, even if Auth was
      // already erased. Status can reconcile completion, never start deletion.
      final beforeStatus = client.auth.currentSession;
      final state =
          await _request({'action': 'status', 'receipt_token': prior});
      _checkOwner(expectedUserId);
      if (client.auth.currentUser != null &&
          !identical(beforeStatus, client.auth.currentSession)) {
        throw const AccountDeletionFailure('session_changed');
      }
      if (_complete(state, expectedUserId)) {
        _completionSessions[expectedUserId] = client.auth.currentSession;
        return;
      }
      if (state.status != 202 ||
          state.data['ok'] != false ||
          state.data['processing'] is! bool) {
        throw const AccountDeletionFailure('unknown');
      }
      if (state.data['processing'] == true) {
        throw const AccountDeletionFailure('deletion_busy');
      }
      if (client.auth.currentUser == null) {
        throw const AccountDeletionFailure('deletion_incomplete');
      }
    }
    if (client.auth.currentUser?.id != expectedUserId) {
      throw const AccountDeletionFailure('session_changed');
    }
    final session = ContentPublicationService(client: client).captureSession();
    try {
      session.check();
      final prepared = await _request(
          {'action': 'prepare', 'client_platform': _web ? 'web' : 'native'},
          token: session.token);
      session.check();
      final data = prepared.data;
      final receipt = data['receipt_token'];
      if (!_complete(prepared, expectedUserId) ||
          receipt is! String ||
          !RegExp(r'^[A-Za-z0-9_-]{43}$').hasMatch(receipt) ||
          data['apple_required'] is! bool) {
        throw const AccountDeletionFailure('unknown');
      }
      if (!_receipts.containsKey(expectedUserId) && _receipts.length >= 8) {
        throw const AccountDeletionFailure('receipt_storage_unavailable');
      }
      _receipts[expectedUserId] = receipt;
      _started[expectedUserId] = DateTime.now().toUtc();
      await _saveReceipts();
      session.check();
      AppleDeletionProof? proof;
      if (data['apple_required'] == true) {
        final nonce = data['nonce'],
            audience = data['client_id'],
            redirect = data['redirect_uri'];
        if (nonce is! String ||
            audience is! String ||
            (redirect != null && redirect is! String)) {
          throw const AccountDeletionFailure('apple_reauthorization_failed');
        }
        proof = await (appleReauthorize ?? _apple)(AppleDeletionChallenge(
            nonce: nonce,
            clientId: audience,
            web: _web,
            redirectUri: redirect is String ? Uri.tryParse(redirect) : null));
        session.check();
      }
      final completed = await _request({
        'action': 'delete',
        'receipt_token': receipt,
        'client_platform': _web ? 'web' : 'native',
        if (proof != null) 'apple_code': proof.authorizationCode,
        if (proof != null) 'apple_identity_token': proof.identityToken,
      }, token: session.token);
      _checkOwner(expectedUserId);
      // Auth may have been erased during this request. A different or renewed
      // login must not consume this operation's completion UI/session cleanup.
      if (client.auth.currentUser != null) session.check();
      if (!_complete(completed, expectedUserId)) {
        throw const AccountDeletionFailure('unknown');
      }
      _completionSessions[expectedUserId] = client.auth.currentSession;
    } on PublicationFailure {
      throw const AccountDeletionFailure('session_changed');
    } on AppleDeletionAuthorizationFailure catch (error) {
      throw AccountDeletionFailure(error.code);
    } finally {
      session.close();
    }
  }

  Future<_DeletionReply> _request(Map<String, dynamic> body,
      {String? token}) async {
    final connection = _transport ?? http.Client();
    try {
      final headers = Map<String, String>.from(client.auth.headers)
        ..removeWhere((key, _) => const {'authorization', 'content-type'}
            .contains(key.toLowerCase()));
      final publicKey = headers.entries
          .firstWhere((entry) => entry.key.toLowerCase() == 'apikey')
          .value;
      headers.addAll({
        'Authorization': 'Bearer ${token ?? publicKey}',
        'Content-Type': 'application/json'
      });
      final endpoint = client.rest.url
          .replaceFirst(RegExp(r'/rest/v1/?$'), '/functions/v1/delete-account');
      final response = await connection
          .post(Uri.parse(endpoint),
              headers: headers,
              body: jsonEncode({'confirmation': 'DELETE', ...body}))
          .timeout(_requestTimeout);
      final data = jsonDecode(response.body);
      if (data is! Map<String, dynamic>) {
        throw const AccountDeletionFailure('unknown');
      }
      if (response.statusCode < 200 || response.statusCode >= 300) {
        final code = data['code'];
        const known = {
          'deletion_unavailable',
          'confirmation_required',
          'apple_revocation_required',
          'deletion_failed',
          'deletion_incomplete',
          'apple_not_configured',
          'deletion_busy',
          'apple_identity_unavailable',
          'apple_reauthorization_required',
          'apple_reauthorization_failed',
          'apple_revocation_failed'
        };
        throw AccountDeletionFailure(response.statusCode == 401
            ? 'session_changed'
            : code is String && known.contains(code)
                ? code
                : response.statusCode == 404
                    ? 'deletion_unavailable'
                    : 'unknown');
      }
      return _DeletionReply(response.statusCode, data);
    } on AccountDeletionFailure {
      rethrow;
    } catch (_) {
      throw const AccountDeletionFailure('unknown');
    } finally {
      if (_transport == null) connection.close();
    }
  }

  Future<bool> clearDeletedSession(String expectedUserId) async {
    if (_completionSessions.containsKey(expectedUserId) &&
        client.auth.currentUser != null &&
        !identical(
            client.auth.currentSession, _completionSessions[expectedUserId])) {
      return false;
    }
    if (client.auth.currentUser?.id != expectedUserId) {
      final cleared = client.auth.currentUser == null;
      if (cleared) await _forgetCompleted(expectedUserId);
      return cleared;
    }
    try {
      await client.auth
          .signOut(scope: SignOutScope.local)
          .timeout(_sessionClearTimeout);
    } catch (_) {/* Local state clears before an attempted remote logout. */}
    final cleared = client.auth.currentUser?.id != expectedUserId;
    if (cleared) await _forgetCompleted(expectedUserId);
    return cleared;
  }
}

class _DeletionReply {
  final int status;
  final Map<String, dynamic> data;
  const _DeletionReply(this.status, this.data);
}

final accountDeletionServiceProvider =
    Provider((ref) => AccountDeletionService());
