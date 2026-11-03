import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/admin_console_provider.dart';
import '../services/admin_console_service.dart';
import 'admin_widgets.dart';

/// PageRoute filtering excludes moderation dialogs from return revalidation.
final adminRouteObserver = RouteObserver<PageRoute<dynamic>>();

/// Constructing a child does not mount it. No child provider/initState runs
/// until an authenticated server response has verified this exact session.
class AdminGate extends ConsumerWidget {
  final Widget child;
  const AdminGate({super.key, required this.child});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final parent = ref.watch(adminConsoleAccessProvider);
    if (parent != null && parent.session.isCurrent) return child;
    return _AdminGateLoader(child: child);
  }
}

class _AdminGateLoader extends ConsumerStatefulWidget {
  final Widget child;
  const _AdminGateLoader({required this.child});
  @override
  ConsumerState<_AdminGateLoader> createState() => _AdminGateLoaderState();
}

class _AdminGateLoaderState extends ConsumerState<_AdminGateLoader>
    with RouteAware {
  AdminConsoleSession? _session;
  StreamSubscription<AdminConsoleFailure>? _subscription;
  AdminConsoleAccess? _access;
  AdminConsoleFailure? _error;
  PageRoute<dynamic>? _route;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final route = ModalRoute.of(context);
    if (route is PageRoute<dynamic> && !identical(route, _route)) {
      adminRouteObserver.unsubscribe(this);
      _route = route;
      adminRouteObserver.subscribe(this, route);
    }
  }

  @override
  void didPopNext() {
    if (mounted) unawaited(_load());
  }

  Future<void> _load() async {
    // Revoke the old subtree and start the new check synchronously. Waiting
    // for stream cleanup here can leave retry showing the previous error.
    unawaited(_subscription?.cancel());
    _subscription = null;
    _session?.close();
    _session = null;
    if (!mounted) return;
    setState(() {
      _access = null;
      _error = null;
    });
    AdminConsoleSession? session;
    try {
      final service = ref.read(adminConsoleServiceProvider);
      session = service.captureSession();
      _session = session;
      _subscription = session.invalidations.listen((failure) {
        if (!mounted || !identical(_session, session)) return;
        setState(() {
          _access = null;
          _error = failure;
        });
      });
      final summary = await service.summary(session);
      session.check();
      if (!mounted || !identical(_session, session)) return;
      setState(() => _access = AdminConsoleAccess(service, session!, summary));
    } catch (error) {
      if (!mounted || !identical(_session, session)) return;
      setState(() => _error = error is AdminConsoleFailure
          ? error
          : const AdminConsoleFailure('network'));
    }
  }

  @override
  void dispose() {
    adminRouteObserver.unsubscribe(this);
    unawaited(_subscription?.cancel());
    _session?.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final access = _access;
    if (access != null && access.session.isCurrent) {
      return ProviderScope(
          overrides: [adminConsoleAccessProvider.overrideWithValue(access)],
          child: KeyedSubtree(
              key: ObjectKey(access.session), child: widget.child));
    }
    return AdminScaffold(
        title: 'Админ хэсэг',
        child: Center(
            child: _error == null
                ? const AdminLoading(message: 'Серверээс эрхийг шалгаж байна…')
                : AdminMessage(
                    icon: _error!.code == 'denied'
                        ? Icons.lock_outline
                        : Icons.cloud_off,
                    title: _error!.code == 'denied'
                        ? 'Хандах эрхгүй'
                        : 'Эрхийг шалгаж чадсангүй',
                    message: _error!.message,
                    onRetry: _load)));
  }
}
