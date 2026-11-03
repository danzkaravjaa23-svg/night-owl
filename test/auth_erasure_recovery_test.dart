import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:night_owl_ub/core/router/app_router.dart';
import 'package:night_owl_ub/core/theme/app_fonts.dart';
import 'package:night_owl_ub/features/auth/screens/auth_landing_screen.dart';
import 'package:night_owl_ub/features/auth/services/apple_auth_service.dart';
import 'package:night_owl_ub/features/profile/services/account_deletion_service.dart';

class _ReceiptProbe extends AccountDeletionService {
  bool available = false;
  bool failed = false;
  Completer<void>? pending;
  int deletionRequests = 0;

  @override
  String? get pendingOwnerId =>
      available ? '10000000-0000-0000-0000-000000000001' : null;

  @override
  Future<void> restorePendingReceipts() async {
    await pending?.future;
    if (failed) {
      throw const AccountDeletionFailure('receipt_storage_unavailable');
    }
  }

  @override
  Future<void> deleteOwnAccount(String expectedUserId,
      {Future<AppleDeletionProof> Function(AppleDeletionChallenge)?
          appleReauthorize}) async {
    deletionRequests++;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  AppFonts.configure();

  Future<void> render(WidgetTester tester, _ReceiptProbe service) async {
    final router = GoRouter(initialLocation: '/auth', routes: [
      GoRoute(
          path: '/auth',
          builder: (_, __) => AuthLandingScreen(deletionService: service)),
      GoRoute(
          path: AppRoutes.deleteAccount,
          builder: (_, __) =>
              const Scaffold(body: Text('Recovery destination'))),
    ]);
    addTearDown(router.dispose);
    await tester.pumpWidget(MaterialApp.router(routerConfig: router));
    await tester.pumpAndSettle();
  }

  testWidgets(
      'saved receipt exposes status recovery without initiating deletion',
      (tester) async {
    final service = _ReceiptProbe()..available = true;
    await render(tester, service);
    final recovery = find.byKey(const ValueKey('auth-deletion-recovery'));
    await tester.ensureVisible(recovery);
    await tester.tap(recovery);
    await tester.pumpAndSettle();
    expect(find.text('Recovery destination'), findsOneWidget);
    expect(service.deletionRequests, 0);
    expect(find.textContaining('10000000-'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  for (final failure in [false, true]) {
    testWidgets(
        'no receipt or inaccessible storage leaves sign-in usable $failure',
        (tester) async {
      final service = _ReceiptProbe()..failed = failure;
      await render(tester, service);
      expect(
          find.byKey(const ValueKey('auth-deletion-recovery')), findsNothing);
      expect(find.text('Имэйлээр нэвтрэх'), findsOneWidget);
      expect(service.deletionRequests, 0);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('late receipt restoration after leaving auth is ignored',
      (tester) async {
    final service = _ReceiptProbe()
      ..available = true
      ..pending = Completer<void>();
    await render(tester, service);
    await tester.pumpWidget(const SizedBox());
    service.pending!.complete();
    await tester.pumpAndSettle();
    expect(service.deletionRequests, 0);
    expect(tester.takeException(), isNull);
  });
}
