import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../services/admin_console_service.dart';

final adminConsoleServiceProvider =
    Provider<AdminConsoleService>((ref) => AdminConsoleService());

/// Only AdminGate installs this value, after the server authorizes the session.
final adminConsoleAccessProvider = Provider<AdminConsoleAccess?>((ref) => null);

class AdminConsoleAccess {
  final AdminConsoleService service;
  final AdminConsoleSession session;
  final AdminConsoleSummary summary;
  const AdminConsoleAccess(this.service, this.session, this.summary);
}

/// A failed later page keeps the earlier rows and offset available for retry.
/// New searches discard old rows immediately and ignore out-of-order results.
class AdminRecordsController extends ChangeNotifier {
  final AdminConsoleAccess access;
  String kind;
  String search = '';
  String status = 'pending';
  List<Map<String, dynamic>> items = [];
  bool loading = false;
  bool hasMore = false;
  AdminConsoleFailure? error;
  int _request = 0;
  bool _disposed = false;
  late final StreamSubscription<AdminConsoleFailure> _subscription;

  AdminRecordsController(this.access, {required this.kind}) {
    _subscription = access.session.invalidations.listen((failure) {
      if (_disposed) return;
      _request++;
      items = [];
      hasMore = false;
      loading = false;
      error = failure;
      notifyListeners();
    });
  }

  Future<void> refresh({String? query, String? filter, String? contentKind}) {
    if (query != null) search = query;
    if (filter != null) status = filter;
    if (contentKind != null) kind = contentKind;
    items = [];
    hasMore = false;
    return _load(0);
  }

  Future<void> loadMore() async {
    if (loading || !hasMore || _disposed) return;
    await _load(items.length);
  }

  Future<void> _load(int offset) async {
    if (_disposed) return;
    final request = ++_request;
    loading = true;
    error = null;
    notifyListeners();
    try {
      final page = await access.service.records(access.session,
          kind: kind, search: search, status: status, offset: offset);
      if (_disposed || request != _request || !access.session.isCurrent) return;
      items = [...items, ...page.items];
      hasMore = page.hasMore;
    } catch (failure) {
      if (_disposed || request != _request || !access.session.isCurrent) return;
      error = failure is AdminConsoleFailure
          ? failure
          : const AdminConsoleFailure('network');
    } finally {
      if (!_disposed && request == _request && access.session.isCurrent) {
        loading = false;
        notifyListeners();
      }
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _request++;
    unawaited(_subscription.cancel());
    super.dispose();
  }
}
