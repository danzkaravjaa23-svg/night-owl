import 'dart:async';

import 'package:night_owl_ub/core/constants/avatar_presets.dart';
import 'package:night_owl_ub/features/admin/services/admin_console_service.dart';

const adminFixtureOwner = '10000000-0000-4000-8000-000000000001';

class AdminFixtureSession extends AdminConsoleSession {
  bool active = true;
  final String owner;
  AdminFixtureSession({this.owner = adminFixtureOwner});
  final _events = StreamController<AdminConsoleFailure>.broadcast();
  @override
  String get ownerId => owner;
  @override
  String get token => 'fixture-captured-token';
  @override
  bool get isCurrent => active;
  @override
  Stream<AdminConsoleFailure> get invalidations => _events.stream;
  @override
  void invalidate(AdminConsoleFailure failure) {
    if (!active) return;
    active = false;
    _events.add(failure);
  }

  @override
  void close() {
    active = false;
    unawaited(_events.close());
  }
}

/// Local-only data shared by widget tests and the visual capture harness.
class AdminConsoleFixtureService extends AdminConsoleService {
  AdminFixtureSession? currentSession;
  AdminConsoleFailure? summaryFailure;
  AdminConsoleFailure? actionFailure;
  Completer<AdminConsoleSummary>? summaryPending;
  Completer<void>? actionPending;
  int summaryCalls = 0;
  final requests =
      <({String kind, String search, String status, int offset})>[];
  final actions = <Map<String, dynamic>>[];
  Future<AdminConsolePage> Function(
      String kind, String search, String status, int offset)? recordHandler;
  final rows = <String, List<Map<String, dynamic>>>{
    'users': [
      {
        'id': 'user-1',
        'username': 'nomin.explores',
        'full_name': 'Номин Эрдэнэ',
        'avatar_url': NightOwlAvatars.all[1].value,
        'is_admin': false,
        'is_banned': false,
        'is_verified': true,
        'created_at': '2026-10-28T12:20:00Z'
      },
      {
        'id': 'user-2',
        'username': 'temuujin.music',
        'full_name': 'Тэмүүжин Бат',
        'avatar_url': NightOwlAvatars.all[0].value,
        'is_admin': false,
        'is_banned': true,
        'is_verified': false,
        'created_at': '2026-10-20T09:15:00Z'
      },
    ],
    'reports': [
      {
        'id': 'report-1',
        'reporter_id': 'reporter-1',
        'reporter_username': 'saruul',
        'target_type': 'post',
        'target_id': 'post-1',
        'target_author_id': 'user-2',
        'target_excerpt':
            'Арга хэмжээний мэдээлэлд хамааралгүй сурталчилгаа давтан нийтэлсэн.',
        'reason': 'spam',
        'details': 'Өчигдрөөс хойш ижил зар хэд хэдэн удаа харагдсан.',
        'status': 'pending',
        'created_at': '2026-11-03T08:40:00Z'
      },
      {
        'id': 'report-2',
        'reporter_id': 'reporter-2',
        'reporter_username': 'erdene',
        'target_type': 'comment',
        'target_id': 'comment-1',
        'target_author_id': 'user-1',
        'target_excerpt': 'Хэрэглэгч рүү чиглэсэн зохисгүй сэтгэгдэл.',
        'reason': 'harassment',
        'details': 'Сэтгэгдлийг шалгаж өгнө үү.',
        'status': 'pending',
        'created_at': '2026-11-03T07:10:00Z'
      },
    ],
    'audit': [
      {
        'id': 'audit-1',
        'actor_id': adminFixtureOwner,
        'actor_username': 'nightowl.team',
        'action': 'resolve_report',
        'target_type': 'report',
        'target_id': 'report-3',
        'reason': 'Мэдээллийг шалгаж, давхардсан сурталчилгааг устгасан.',
        'created_at': '2026-11-03T06:30:00Z'
      },
      {
        'id': 'audit-2',
        'actor_id': adminFixtureOwner,
        'actor_username': 'nightowl.team',
        'action': 'verify_user',
        'target_type': 'user',
        'target_id': 'user-1',
        'reason': 'Бүртгэлийн мэдээллийг баталгаажуулсан.',
        'created_at': '2026-11-02T13:20:00Z'
      },
    ],
    'post': [
      {
        'id': 'post-1',
        'author_id': 'user-1',
        'username': 'nomin.explores',
        'body':
            'Хотын гэрэл, амьд хөгжимтэй сайхан үдэш. Энэ долоо хоногт сонсох дуртай газраа хуваалцаарай.',
        'media_url': null,
        'created_at': '2026-11-03T07:00:00Z'
      },
    ],
    'comment': [
      {
        'id': 'comment-1',
        'author_id': 'user-2',
        'username': 'temuujin.music',
        'body': 'Энэ газрын амьд хөгжмийн хөтөлбөр хэдэн цагаас эхлэх вэ?',
        'media_url': null,
        'created_at': '2026-11-03T07:15:00Z'
      },
    ],
  };

  @override
  AdminConsoleSession captureSession() =>
      currentSession = AdminFixtureSession();
  @override
  Future<AdminConsoleSummary> summary(AdminConsoleSession session) async {
    summaryCalls++;
    session.check();
    if (summaryFailure != null) throw summaryFailure!;
    final result = await (summaryPending?.future ??
        Future.value(AdminConsoleSummary(session.ownerId!, const {
          'users': 1248,
          'posts': 386,
          'comments': 924,
          'venues': 48,
          'events': 16,
          'pending_reports': 2,
          'banned_users': 7,
        })));
    session.check();
    return result;
  }

  @override
  Future<AdminConsolePage> records(AdminConsoleSession session,
      {required String kind,
      String search = '',
      String status = 'pending',
      int offset = 0,
      int limit = 30}) async {
    session.check();
    requests.add((kind: kind, search: search, status: status, offset: offset));
    final result = recordHandler != null
        ? await recordHandler!(kind, search, status, offset)
        : AdminConsolePage(
            items: (rows[kind] ?? [])
                .where((row) =>
                    (kind != 'reports' || row['status'] == status) &&
                    (search.isEmpty ||
                        row
                            .toString()
                            .toLowerCase()
                            .contains(search.toLowerCase())))
                .map((row) => Map<String, dynamic>.from(row))
                .toList(),
            hasMore: false);
    session.check();
    return result;
  }

  @override
  Future<Map<String, dynamic>> action(AdminConsoleSession session,
      {required String action,
      required String targetId,
      required String reason,
      String? reportId}) async {
    session.check();
    if (reason.trim().length < 3) throw const AdminConsoleFailure('reason');
    actions.add({
      'action': action,
      'target_id': targetId,
      'reason': reason,
      'report_id': reportId
    });
    await actionPending?.future;
    session.check();
    if (actionFailure != null) throw actionFailure!;
    for (final row in rows['reports']!) {
      if (row['id'] == reportId || row['id'] == targetId) {
        row['status'] = action == 'reopen_report'
            ? 'pending'
            : action == 'dismiss_report'
                ? 'reviewed'
                : 'resolved';
      }
    }
    return {
      'audit_id': 'fixture-audit',
      'action': action,
      'target_id': targetId
    };
  }
}
