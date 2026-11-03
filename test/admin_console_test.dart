import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:night_owl_ub/core/theme/app_colors.dart';
import 'package:night_owl_ub/core/theme/app_theme.dart';
import 'package:night_owl_ub/features/admin/providers/admin_console_provider.dart';
import 'package:night_owl_ub/features/admin/screens/admin_panel_screen.dart';
import 'package:night_owl_ub/features/admin/screens/admin_users_screen.dart';
import 'package:night_owl_ub/features/admin/screens/admin_reports_screen.dart';
import 'package:night_owl_ub/features/admin/screens/admin_audit_screen.dart';
import 'package:night_owl_ub/features/admin/screens/admin_content_screen.dart';
import 'package:night_owl_ub/features/admin/services/admin_console_service.dart';
import 'package:night_owl_ub/features/admin/widgets/admin_gate.dart';
import 'admin_console_fixture.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late AdminConsoleFixtureService service;
  setUp(() {
    GoogleFonts.config.allowRuntimeFetching = false;
    service = AdminConsoleFixtureService();
  });
  Future<void> render(WidgetTester tester, Widget screen,
      {double width = 390, double scale = 1, bool dark = true}) async {
    tester.view.physicalSize = Size(width, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(() => AppColors.isDarkMode = true);
    AppColors.isDarkMode = dark;
    await tester.pumpWidget(ProviderScope(
        overrides: [
          adminConsoleServiceProvider.overrideWithValue(service),
        ],
        child: MaterialApp(
            navigatorObservers: [adminRouteObserver],
            theme: dark ? AppTheme.dark : AppTheme.light,
            builder: (context, child) => MediaQuery(
                data: MediaQuery.of(context)
                    .copyWith(textScaler: TextScaler.linear(scale)),
                child: child!),
            home: screen)));
    await tester.pump();
  }

  Future<void> openReportAction(WidgetTester tester) async {
    await tester.tap(find.byTooltip('Удирдах үйлдлүүд').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Шийдвэрлэсэн гэж тэмдэглэх'));
    await tester.pumpAndSettle();
  }

  testWidgets('server denied gate never mounts users or issues list requests',
      (tester) async {
    service.summaryFailure = const AdminConsoleFailure('denied');
    await render(tester, const AdminUsersScreen());
    await tester.pumpAndSettle();
    expect(find.text('Хандах эрхгүй'), findsOneWidget);
    expect(service.summaryCalls, 1);
    expect(service.requests, isEmpty);
    expect(find.byType(TextField), findsNothing);
  });
  testWidgets(
      'returning from a page hides cached admin child until fresh server authorization',
      (tester) async {
    final protected = AdminGate(child: Builder(builder: (context) {
      return Scaffold(
          body: TextButton(
              onPressed: () {
                Navigator.of(context)
                    .push(MaterialPageRoute<void>(builder: (context) {
                  return Scaffold(
                      body: TextButton(
                          onPressed: () => Navigator.of(context).pop(),
                          child: const Text('Return')));
                }));
              },
              child: const Text('Authorized admin details')));
    }));
    await render(tester, protected);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Authorized admin details'));
    await tester.pumpAndSettle();
    service.summaryPending = Completer<AdminConsoleSummary>();
    await tester.tap(find.text('Return'));
    await tester.pump(const Duration(milliseconds: 400));
    expect(service.summaryCalls, 2);
    expect(find.text('Authorized admin details'), findsNothing);
    expect(find.text('Серверээс эрхийг шалгаж байна…'), findsOneWidget);
    service.summaryPending!.completeError(const AdminConsoleFailure('denied'));
    await tester.pumpAndSettle();
    expect(find.text('Хандах эрхгүй'), findsOneWidget);
    expect(find.text('Authorized admin details'), findsNothing);
  });
  testWidgets(
      'pending authorization mounts no report child until server result',
      (tester) async {
    service.summaryPending = Completer<AdminConsoleSummary>();
    await render(tester, const AdminReportsScreen());
    expect(service.requests, isEmpty);
    expect(find.text('Спам'), findsNothing);
    service.summaryPending!
        .complete(const AdminConsoleSummary(adminFixtureOwner, {}));
    await tester.pumpAndSettle();
    expect(service.requests.single.kind, 'reports');
    expect(find.text('Спам'), findsOneWidget);
  });
  testWidgets('missing migration shows recovery instead of an empty dashboard',
      (tester) async {
    service.summaryFailure = const AdminConsoleFailure('unavailable');
    await render(tester, const AdminPanelScreen());
    await tester.pumpAndSettle();
    expect(find.textContaining('хараахан суулгагдаагүй'), findsOneWidget);
    expect(find.text('Хамт олноо хамгаалъя'), findsNothing);
    service.summaryFailure = null;
    await tester.tap(find.text('Дахин оролдох'));
    await tester.pumpAndSettle();
    expect(service.summaryCalls, 2);
    expect(find.text('Хамт олноо хамгаалъя'), findsOneWidget);
  });
  testWidgets(
      'reason is required and rejected action remains visible without optimistic success',
      (tester) async {
    service.actionFailure = const AdminConsoleFailure('conflict');
    await render(tester, const AdminReportsScreen());
    await tester.pumpAndSettle();
    await openReportAction(tester);
    await tester.tap(find.text('Баталгаажуулах'));
    await tester.pumpAndSettle();
    expect(service.actions, isEmpty);
    expect(find.textContaining('3–1000'), findsOneWidget);
    await tester.enterText(find.byType(TextField), 'Контентыг шалгасан');
    await tester.tap(find.text('Баталгаажуулах'));
    await tester.pumpAndSettle();
    expect(service.actions, hasLength(1));
    expect(find.textContaining('Мэдээлэл өөрчлөгдсөн'), findsOneWidget);
    expect(service.rows['reports']!.first['status'], 'pending');
    expect(find.text('Үйлдлийг хадгалж, аудитын түүхэнд бүртгэлээ.'),
        findsNothing);
  });
  testWidgets(
      'pending action is disabled and success is shown only after receipt',
      (tester) async {
    service.actionPending = Completer<void>();
    await render(tester, const AdminReportsScreen());
    await tester.pumpAndSettle();
    await openReportAction(tester);
    await tester.enterText(find.byType(TextField), 'Контентыг шалгасан');
    await tester.tap(find.text('Баталгаажуулах'));
    await tester.pump();
    expect(service.rows['reports']!.first['status'], 'pending');
    expect(
        tester
            .widget<FilledButton>(
                find.widgetWithText(FilledButton, 'Хадгалж байна…'))
            .onPressed,
        isNull);
    service.actionPending!.complete();
    await tester.pumpAndSettle();
    expect(service.rows['reports']!.first['status'], 'resolved');
    expect(find.text('Спам'), findsNothing);
    expect(find.text('Үйлдлийг хадгалж, аудитын түүхэнд бүртгэлээ.'),
        findsOneWidget);
  });
  testWidgets(
      'account change removes report data and open confirmation before a late completion',
      (tester) async {
    service.actionPending = Completer<void>();
    await render(tester, const AdminReportsScreen());
    await tester.pumpAndSettle();
    await openReportAction(tester);
    await tester.enterText(find.byType(TextField), 'Контентыг шалгасан');
    await tester.tap(find.text('Баталгаажуулах'));
    await tester.pump();
    service.currentSession!
        .invalidate(const AdminConsoleFailure('session_changed'));
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsNothing);
    expect(find.text('Спам'), findsNothing);
    expect(find.textContaining('Нэвтрэх бүртгэл өөрчлөгдлөө'), findsOneWidget);
    service.actionPending!.complete();
    await tester.pumpAndSettle();
    expect(find.text('Үйлдлийг хадгалж, аудитын түүхэнд бүртгэлээ.'),
        findsNothing);
    expect(tester.takeException(), isNull);
  });
  testWidgets(
      'uncertain action warns against retry and disables repeat submission',
      (tester) async {
    service.actionFailure = const AdminConsoleFailure('action_uncertain');
    await render(tester, const AdminReportsScreen());
    await tester.pumpAndSettle();
    await openReportAction(tester);
    await tester.enterText(find.byType(TextField), 'Контентыг шалгасан');
    await tester.tap(find.text('Баталгаажуулах'));
    await tester.pumpAndSettle();
    expect(find.textContaining('хадгалагдсан байж болно'), findsOneWidget);
    expect(
        tester
            .widget<FilledButton>(
                find.widgetWithText(FilledButton, 'Баталгаажуулах'))
            .onPressed,
        isNull);
    expect(service.actions, hasLength(1));
  });
  for (final dark in [true, false]) {
    for (final entry in const [
      ('dashboard', AdminPanelScreen()),
      ('users', AdminUsersScreen()),
      ('reports', AdminReportsScreen()),
      ('audit', AdminAuditScreen()),
      ('content', AdminContentScreen()),
    ]) {
      testWidgets(
          '${entry.$1} remains readable at 320px large text in ${dark ? 'night' : 'day'}',
          (tester) async {
        await render(tester, entry.$2, width: 320, scale: 1.5, dark: dark);
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        expect(service.summaryCalls, 1);
        await tester.drag(find.byType(ListView).first, const Offset(0, -500));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
      });
    }
  }

  group('records controller', () {
    late AdminFixtureSession session;
    late AdminRecordsController records;
    setUp(() {
      session = AdminFixtureSession();
      records = AdminRecordsController(
          AdminConsoleAccess(service, session,
              const AdminConsoleSummary(adminFixtureOwner, {})),
          kind: 'users');
    });
    tearDown(() {
      records.dispose();
      session.close();
    });
    test('failed next page retains rows and retries the same offset', () async {
      var failNext = true;
      service.recordHandler = (_, __, ___, offset) async {
        if (offset == 0) {
          return const AdminConsolePage(items: [
            {'id': 'first'}
          ], hasMore: true);
        }
        if (failNext) throw const AdminConsoleFailure('network');
        return const AdminConsolePage(items: [
          {'id': 'second'}
        ], hasMore: false);
      };
      await records.refresh();
      await records.loadMore();
      expect(records.items.single['id'], 'first');
      expect(records.error?.code, 'network');
      expect(records.hasMore, isTrue);
      failNext = false;
      await records.loadMore();
      expect(records.items.map((row) => row['id']), ['first', 'second']);
      expect(service.requests.map((request) => request.offset), [0, 1, 1]);
      expect(records.hasMore, isFalse);
    });
    test(
        'new search ignores older response and scope change clears visible data',
        () async {
      final old = Completer<AdminConsolePage>();
      final current = Completer<AdminConsolePage>();
      service.recordHandler =
          (_, search, __, ___) => search == 'old' ? old.future : current.future;
      final oldLoad = records.refresh(query: 'old');
      final newLoad = records.refresh(query: 'new');
      current.complete(const AdminConsolePage(items: [
        {'id': 'new'}
      ], hasMore: false));
      await newLoad;
      old.complete(const AdminConsolePage(items: [
        {'id': 'old'}
      ], hasMore: true));
      await oldLoad;
      expect(records.items.single['id'], 'new');
      session.invalidate(const AdminConsoleFailure('session_changed'));
      await Future<void>.delayed(Duration.zero);
      expect(records.items, isEmpty);
      expect(records.error?.code, 'session_changed');
    });
  });
}
