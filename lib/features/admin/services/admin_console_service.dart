import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/services/supabase_service.dart';

class AdminConsoleFailure implements Exception {
  final String code;
  const AdminConsoleFailure(this.code);

  String get message => switch (code) {
        'denied' =>
          'Энэ бүртгэлд админы эрх байхгүй эсвэл эрх нь цуцлагдсан байна.',
        'authentication' => 'Нэвтрэх эрх дууссан байна. Дахин нэвтэрнэ үү.',
        'session_changed' =>
          'Нэвтрэх бүртгэл өөрчлөгдлөө. Эрхээ дахин шалгана уу.',
        'unavailable' => 'Админ үйлчилгээ серверт хараахан суулгагдаагүй байна. '
            'Админ консолын өгөгдлийн сангийн шинэчлэлийг суулгасны дараа дахин шалгана уу.',
        'reason' => 'Шалтгаанаа 3–1000 тэмдэгтээр бичнэ үү.',
        'invalid' => 'Хүсэлтийн мэдээлэл буруу байна. Сонголтоо шалгана уу.',
        'missing' =>
          'Энэ мэдээлэл устсан эсвэл олдсонгүй. Жагсаалтыг шинэчилнэ үү.',
        'conflict' =>
          'Мэдээлэл өөрчлөгдсөн байна. Жагсаалтыг шинэчилж дахин шалгана уу.',
        'response' =>
          'Серверийн хариуг баталгаажуулж чадсангүй. Жагсаалтыг шинэчилнэ үү.',
        'action_uncertain' =>
          'Хариу ирээгүй ч үйлдэл серверт хадгалагдсан байж болно. '
              'Дахин илгээхээс өмнө жагсаалт болон үйлдлийн түүхийг шинэчилж шалгана уу.',
        _ =>
          'Сервертэй холбогдож чадсангүй. Холболтоо шалгаад дахин оролдоно уу.',
      };

  @override
  String toString() => message;
}

abstract class AdminConsoleSession {
  String? get ownerId;
  String get token;
  bool get isCurrent;
  Stream<AdminConsoleFailure> get invalidations;
  void invalidate(AdminConsoleFailure failure);
  void close();

  void check() {
    if (isCurrent) return;
    final failure = AdminConsoleFailure(
        ownerId == null ? 'authentication' : 'session_changed');
    invalidate(failure);
    throw failure;
  }
}

class _AuthAdminSession extends AdminConsoleSession {
  final SupabaseClient client;
  final void Function() onClose;
  final Session? _captured;
  Session? _allowed;
  bool _stale = false;
  final _invalidations = StreamController<AdminConsoleFailure>.broadcast();
  late final StreamSubscription<AuthState> _subscription;

  _AuthAdminSession(this.client, {required this.onClose})
      : _captured = client.auth.currentSession,
        _allowed = client.auth.currentSession {
    var first = true;
    _subscription = client.auth.onAuthStateChange.listen((state) {
      if (first && identical(state.session, _captured)) {
        first = false;
        return;
      }
      first = false;
      if (!_stale &&
          (state.event == AuthChangeEvent.tokenRefreshed ||
              state.event == AuthChangeEvent.userUpdated) &&
          state.session?.user.id == ownerId) {
        _allowed = state.session;
      } else {
        invalidate(const AdminConsoleFailure('session_changed'));
      }
    }, onError: (Object _) {
      invalidate(const AdminConsoleFailure('authentication'));
    });
  }

  @override
  String? get ownerId => _captured?.user.id;
  @override
  String get token => _allowed?.accessToken ?? '';
  @override
  bool get isCurrent =>
      !_stale &&
      ownerId != null &&
      client.auth.currentUser?.id == ownerId &&
      identical(client.auth.currentSession, _allowed);
  @override
  Stream<AdminConsoleFailure> get invalidations => _invalidations.stream;
  @override
  void invalidate(AdminConsoleFailure failure) {
    if (_stale) return;
    _stale = true;
    if (!_invalidations.isClosed) _invalidations.add(failure);
  }

  @override
  void close() {
    _stale = true;
    onClose();
    unawaited(_subscription.cancel());
    unawaited(_invalidations.close());
  }
}

class AdminConsoleSummary {
  final String actorId;
  final Map<String, int> counts;
  const AdminConsoleSummary(this.actorId, this.counts);
}

class AdminConsolePage {
  final List<Map<String, dynamic>> items;
  final bool hasMore;
  const AdminConsolePage({required this.items, required this.hasMore});
}

/// All reads and mutations use server-authorized RPCs. The raw transport pins
/// the captured token and never lets the SDK refresh or replace another login.
class AdminConsoleService {
  final SupabaseClient? _client;
  final http.Client? _httpClient;
  final Duration requestTimeout;
  final _sessions = <AdminConsoleSession>{};
  AdminConsoleService(
      {SupabaseClient? client,
      http.Client? httpClient,
      this.requestTimeout = const Duration(seconds: 20)})
      : _client = client,
        _httpClient = httpClient;

  SupabaseClient get client => _client ?? SupabaseService.client;
  AdminConsoleSession captureSession() {
    late final AdminConsoleSession session;
    session =
        _AuthAdminSession(client, onClose: () => _sessions.remove(session));
    _sessions.add(session);
    return session;
  }

  void _invalidateAccount(
      AdminConsoleSession session, AdminConsoleFailure failure) {
    // A pushed admin route must also remove cached sensitive data on routes
    // beneath it when the server revokes the account's access.
    for (final scope in _sessions.toList()) {
      if (scope.ownerId == session.ownerId) scope.invalidate(failure);
    }
    session.invalidate(failure);
  }

  Future<dynamic> callRpc(AdminConsoleSession session, String name,
      Map<String, dynamic> parameters) async {
    if (!const {
      'admin_console_summary',
      'admin_console_users',
      'admin_console_reports',
      'admin_console_audit',
      'admin_console_content',
      'admin_console_action',
      'get_pilot_overview',
      'search_pilot_candidates',
      'set_pilot_entry',
      'review_venue',
      'get_admin_featured_events',
      'set_featured_event',
    }.contains(name)) {
      throw const AdminConsoleFailure('invalid');
    }
    session.check();
    final connection = _httpClient ?? http.Client();
    try {
      final headers = Map<String, String>.from(client.auth.headers)
        ..removeWhere((key, _) =>
            key.toLowerCase() == 'authorization' ||
            key.toLowerCase() == 'content-type')
        ..addAll({
          'Authorization': 'Bearer ${session.token}',
          'Content-Type': 'application/json',
        });
      final response = await connection
          .post(Uri.parse('${client.rest.url}/rpc/$name'),
              headers: headers, body: jsonEncode(parameters))
          .timeout(requestTimeout);
      session.check();
      dynamic body;
      try {
        body = jsonDecode(response.body);
      } catch (_) {
        body = null;
      }
      if (response.statusCode < 200 || response.statusCode >= 300) {
        final code = body is Map ? body['code'] : null;
        final failure = AdminConsoleFailure(response.statusCode == 401
            ? 'authentication'
            : response.statusCode == 403 || code == '42501'
                ? 'denied'
                : code == 'PGRST202' ||
                        code == '42883' ||
                        (response.statusCode == 404 && code != 'P0002')
                    ? 'unavailable'
                    : code == '22023'
                        ? 'invalid'
                        : code == 'P0002'
                            ? 'missing'
                            : code == '40001'
                                ? 'conflict'
                                : 'network');
        if (failure.code == 'authentication' || failure.code == 'denied') {
          _invalidateAccount(session, failure);
        }
        throw failure;
      }
      return body;
    } on AdminConsoleFailure {
      rethrow;
    } catch (_) {
      session.check();
      throw const AdminConsoleFailure('network');
    } finally {
      if (_httpClient == null) connection.close();
    }
  }

  Future<Map<String, dynamic>> _rpc(AdminConsoleSession session, String name,
      Map<String, dynamic> parameters) async {
    final data = await callRpc(session, name, parameters);
    session.check();
    if (data is! Map<String, dynamic>) {
      throw const AdminConsoleFailure('response');
    }
    return data;
  }

  Future<AdminConsoleSummary> summary(AdminConsoleSession session) async {
    final data = await _rpc(session, 'admin_console_summary', {});
    session.check();
    if (data['actor_id'] != session.ownerId) {
      session.invalidate(const AdminConsoleFailure('response'));
      throw const AdminConsoleFailure('response');
    }
    final counts = <String, int>{};
    for (final name in const [
      'users',
      'posts',
      'comments',
      'venues',
      'events',
      'pending_reports',
      'banned_users'
    ]) {
      final value = data[name];
      if (value is! int || value < 0) {
        throw const AdminConsoleFailure('response');
      }
      counts[name] = value;
    }
    return AdminConsoleSummary(session.ownerId!, Map.unmodifiable(counts));
  }

  Future<AdminConsolePage> records(AdminConsoleSession session,
      {required String kind,
      String search = '',
      String status = 'pending',
      int offset = 0,
      int limit = 30}) async {
    if (!const {'users', 'reports', 'audit', 'post', 'comment'}
            .contains(kind) ||
        search.trim().runes.length > 100 ||
        offset < 0 ||
        offset > 100000 ||
        limit < 1 ||
        limit > 100 ||
        !const {'pending', 'resolved', 'reviewed'}.contains(status)) {
      throw const AdminConsoleFailure('invalid');
    }
    final content = kind == 'post' || kind == 'comment';
    final data =
        await _rpc(session, 'admin_console_${content ? 'content' : kind}', {
      'p_offset': offset,
      'p_limit': limit,
      if (kind == 'users' || content) 'p_search': search.trim(),
      if (kind == 'reports') 'p_status': status,
      if (content) 'p_kind': kind,
    });
    final items = data['items'];
    session.check();
    if (items is! List ||
        data['has_more'] is! bool ||
        items.any((item) =>
            item is! Map<String, dynamic> ||
            item['id'] is! String ||
            (item['id'] as String).isEmpty)) {
      throw const AdminConsoleFailure('response');
    }
    return AdminConsolePage(
        items: List.unmodifiable(items.cast<Map<String, dynamic>>()),
        hasMore: data['has_more'] as bool);
  }

  Future<Map<String, dynamic>> action(AdminConsoleSession session,
      {required String action,
      required String targetId,
      required String reason,
      String? reportId}) async {
    session.check();
    final explanation = reason.trim();
    if (explanation.runes.length < 3 || explanation.runes.length > 1000) {
      throw const AdminConsoleFailure('reason');
    }
    if (!const {
          'ban_user',
          'unban_user',
          'verify_user',
          'unverify_user',
          'delete_post',
          'delete_comment',
          'resolve_report',
          'dismiss_report',
          'reopen_report'
        }.contains(action) ||
        targetId.isEmpty) {
      throw const AdminConsoleFailure('invalid');
    }
    late final Map<String, dynamic> receipt;
    try {
      receipt = await _rpc(session, 'admin_console_action', {
        'p_action': action,
        'p_target_id': targetId,
        'p_reason': explanation,
        if (reportId != null) 'p_report_id': reportId,
      });
    } on AdminConsoleFailure catch (failure) {
      if (failure.code == 'network' || failure.code == 'response') {
        throw const AdminConsoleFailure('action_uncertain');
      }
      rethrow;
    }
    final reportAction = action.endsWith('_report');
    session.check();
    final expectedReport = reportAction ? targetId : reportId;
    final expectedStatus = expectedReport == null
        ? null
        : action == 'reopen_report'
            ? 'pending'
            : action == 'dismiss_report'
                ? 'reviewed'
                : 'resolved';
    final expectedType = reportAction
        ? 'report'
        : action.endsWith('_user')
            ? 'user'
            : action == 'delete_post'
                ? 'post'
                : 'comment';
    if (receipt['action'] != action ||
        receipt['target_id'] != targetId ||
        receipt['target_type'] != expectedType ||
        receipt['report_id'] != expectedReport ||
        receipt['report_status'] != expectedStatus ||
        receipt['audit_id'] is! String ||
        !RegExp(r'^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$',
                caseSensitive: false)
            .hasMatch(receipt['audit_id'] as String) ||
        receipt['created_at'] is! String ||
        DateTime.tryParse(receipt['created_at'] as String) == null) {
      throw const AdminConsoleFailure('action_uncertain');
    }
    return receipt;
  }
}
