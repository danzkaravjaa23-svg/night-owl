import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:night_owl_ub/core/theme/app_colors.dart';
import 'package:night_owl_ub/core/theme/app_theme.dart';
import 'package:night_owl_ub/features/dm/services/note_service.dart';
import 'package:night_owl_ub/features/dm/widgets/create_group_sheet.dart';
import 'package:night_owl_ub/features/dm/widgets/notes_row.dart';
import 'package:night_owl_ub/features/profile/widgets/invite_sheet.dart';

/// DS-02: bottomSheetTheme (showDragHandle: true) нэг Material бариул зурдаг.
/// Sheet-үүд өөрсдөө дахин 40×4 бариул зурж, хоёр бариул давхардаж байсан.
/// Энэ тест sheet бүрт яг НЭГ бариул харагдахыг шалгана.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const account = '10000000-0000-4000-8000-000000000001';
  late http.Client transport;

  http.Response json(http.Request request, Object? body) =>
      http.Response(jsonEncode(body), 200,
          request: request, headers: {'content-type': 'application/json'});

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    GoogleFonts.config.allowRuntimeFetching = false;
    transport = MockClient((request) async {
      if (request.url.path == '/auth/v1/token') {
        final payload = base64Url
            .encode(utf8.encode(jsonEncode({
              'sub': account,
              'exp': DateTime.now().millisecondsSinceEpoch ~/ 1000 + 3600,
            })))
            .replaceAll('=', '');
        return json(request, {
          'access_token': 'fixture.$payload.fixture',
          'refresh_token': 'fixture-refresh',
          'token_type': 'bearer',
          'expires_in': 3600,
          'user': {
            'id': account,
            'aud': 'authenticated',
            'created_at': '2026-11-03T00:00:00Z',
          },
        });
      }
      if (request.url.path.endsWith('/profiles')) {
        return json(request, {'id': account, 'username': 'fixture'});
      }
      return json(request, []);
    });
    await Supabase.initialize(
        url: 'https://sheet-handle.example.test',
        anonKey: 'fixture-public-key',
        debug: false,
        authOptions: const FlutterAuthClientOptions(
            autoRefreshToken: false,
            detectSessionInUri: false,
            localStorage: EmptyLocalStorage()),
        httpClient: transport);
    await Supabase.instance.client.auth.signInWithPassword(
        email: 'fixture@example.test', password: 'fixture-password');
  });

  tearDown(() async {
    await Supabase.instance.dispose();
    transport.close();
  });

  Future<void> render(WidgetTester tester, bool dark, Widget body) async {
    tester.view.physicalSize = const Size(390, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(() => AppColors.isDarkMode = true);
    AppColors.isDarkMode = dark;
    await tester.pumpWidget(ProviderScope(
        overrides: [
          noteServiceProvider.overrideWithValue(NoteService(
              client: Supabase.instance.client, transport: transport)),
        ],
        child: MaterialApp(
            theme: dark ? AppTheme.dark : AppTheme.light,
            home: Scaffold(body: body))));
    await tester.pumpAndSettle();
  }

  /// Sheet доторх "бариул" хэлбэртэй хайрцгууд: 4 px өндөр, 30-48 px өргөн,
  /// булантай BoxDecoration. Material-ийн бариул (36×4) ч, гараар зурсан
  /// 40×4 бариул ч энэ шүүлтүүрт орно — өмнө нь 2 тоологддог байсан.
  int handleCount(WidgetTester tester) {
    final sheet = find.byType(BottomSheet);
    expect(sheet, findsOneWidget);
    final boxes = find.descendant(
        of: sheet,
        matching: find.byWidgetPredicate((w) =>
            w is DecoratedBox &&
            w.decoration is BoxDecoration &&
            (w.decoration as BoxDecoration).borderRadius != null));
    return boxes.evaluate().where((element) {
      final box = element.renderObject;
      if (box is! RenderBox || !box.hasSize) return false;
      final size = box.size;
      return size.height == 4 && size.width >= 30 && size.width <= 48;
    }).length;
  }

  Widget opener(String label, Future<void> Function(BuildContext) open) =>
      Builder(
          builder: (context) => Center(
              child: TextButton(
                  onPressed: () => open(context), child: Text(label))));

  for (final dark in [true, false]) {
    final mode = dark ? 'Night' : 'Day';

    testWidgets('Create-group sheet shows exactly one drag handle ($mode)',
        (tester) async {
      await render(tester, dark,
          opener('Групп нээх', (context) => showCreateGroupSheet(context)));
      await tester.tap(find.text('Групп нээх'));
      await tester.pumpAndSettle();
      expect(find.text('Групп чат үүсгэх'), findsOneWidget);
      expect(handleCount(tester), 1);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();
    });

    testWidgets('Note composer and its venue picker show one handle ($mode)',
        (tester) async {
      await render(tester, dark, const NotesRow());
      await tester.tap(find.text('Note үлдээх...'));
      await tester.pumpAndSettle();
      expect(find.text('Найзууд чинь 24 цаг харна'), findsOneWidget);
      expect(handleCount(tester), 1);
      // Composer дээрээс нээгдэх газар сонгох sheet — тус бүр нэг бариултай.
      await tester.tap(find.text('Газар тэмдэглэх (заавал биш)'));
      await tester.pumpAndSettle();
      expect(find.text('Газар сонгох'), findsOneWidget);
      final sheets = find.byType(BottomSheet);
      expect(sheets, findsNWidgets(2));
      for (final element in sheets.evaluate()) {
        final handles = find
            .descendant(
                of: find.byWidget(element.widget),
                matching: find.byWidgetPredicate((w) =>
                    w is DecoratedBox &&
                    w.decoration is BoxDecoration &&
                    (w.decoration as BoxDecoration).borderRadius != null))
            .evaluate()
            .where((e) {
          final box = e.renderObject;
          if (box is! RenderBox || !box.hasSize) return false;
          return box.size.height == 4 &&
              box.size.width >= 30 &&
              box.size.width <= 48;
        });
        expect(handles.length, 1);
      }
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();
    });

    testWidgets('Invite sheet shows exactly one drag handle ($mode)',
        (tester) async {
      await render(tester, dark,
          opener('Урилга нээх', (context) => showInviteSheet(context)));
      await tester.tap(find.text('Урилга нээх'));
      await tester.pumpAndSettle();
      expect(find.text('Найзаа урих'), findsOneWidget);
      expect(handleCount(tester), 1);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();
    });
  }
}
