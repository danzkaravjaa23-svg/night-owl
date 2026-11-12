import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:night_owl_ub/core/constants/community_rules.dart';
import 'package:night_owl_ub/core/theme/app_colors.dart';
import 'package:night_owl_ub/core/widgets/gradient_button.dart';
import 'package:night_owl_ub/features/auth/screens/setup_screen.dart';
import 'package:night_owl_ub/features/auth/services/account_metadata_service.dart';
import 'package:night_owl_ub/features/auth/widgets/auth_ui.dart';

// Harness copied from setup_avatar_test.dart: a real Supabase client over a
// MockClient, signed in with fixture metadata, rendering SetupScreen in a
// GoRouter with stub destinations.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const me = 'fixture-user';
  var signInId = me;
  var setupComplete = true;
  var communityAccepted = false;
  Map<String, dynamic>? profile;
  late List<Map<String, dynamic>> writes;
  var metadataWrites = 0;
  late http.Client transport;
  var rejectLoad = false;
  var failLogout = false;
  var failMetadata = false;
  http.Response response(http.Request request, Object? body,
          [int status = 200]) =>
      http.Response(jsonEncode(body), status,
          headers: {'content-type': 'application/json'}, request: request);
  Map<String, dynamic> user(String id) => {
        'id': id,
        'aud': 'authenticated',
        'created_at': '2026-10-07T00:00:00Z',
        'user_metadata': {
          'setup_complete': setupComplete,
          if (communityAccepted)
            ...CommunityRules.acceptance(DateTime.utc(2026, 11, 3)),
        },
      };
  http.Response metadataResponse(http.Request request) {
    final authorization = request.headers.entries
        .firstWhere((entry) => entry.key.toLowerCase() == 'authorization')
        .value;
    final payload = jsonDecode(utf8.decode(base64Url.decode(
        base64Url.normalize(authorization.substring(7).split('.')[1])))) as Map;
    final owner = user(payload['sub'] as String);
    return response(request, {
      ...owner,
      'user_metadata': {
        ...owner['user_metadata'] as Map<String, dynamic>,
        ...(jsonDecode(request.body) as Map)['data'] as Map<String, dynamic>,
      },
    });
  }

  Map<String, dynamic> savedProfile() => {
        'id': me,
        'username': 'fixture_user',
        'full_name': 'Fixture',
        'bio': 'Saved bio',
        'avatar_url': null,
        'interests': <String>[]
      };

  Future<void> signIn([String id = me]) async {
    signInId = id;
    await Supabase.instance.client.auth.signInWithPassword(
        email: '$id@example.test', password: 'fixture-password');
  }

  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    profile = savedProfile();
    writes = [];
    transport = MockClient((request) async {
      final path = request.url.path;
      if (path == '/auth/v1/token') {
        final payload = base64Url
            .encode(utf8.encode(jsonEncode({
              'sub': signInId,
              'exp': DateTime.now().millisecondsSinceEpoch ~/ 1000 + 3600,
            })))
            .replaceAll('=', '');
        return response(request, {
          'access_token': 'fixture.$payload.fixture',
          'refresh_token': 'fixture-refresh',
          'token_type': 'bearer',
          'expires_in': 3600,
          'user': user(signInId)
        });
      }
      if (path == '/auth/v1/logout') {
        return failLogout
            ? response(request, {'message': 'unavailable'}, 500)
            : http.Response('', 204, request: request);
      }
      if (path == '/rest/v1/profiles' && request.method == 'GET') {
        return rejectLoad
            ? response(request, {'message': 'offline', 'code': 'XX000'}, 400)
            : response(request, profile == null ? [] : [profile]);
      }
      if (path == '/rest/v1/profiles' && request.method == 'POST') {
        writes.add(Map<String, dynamic>.from(jsonDecode(request.body) as Map));
        return response(request, {});
      }
      if (path == '/auth/v1/user' && request.method == 'PUT') {
        metadataWrites++;
        return failMetadata
            ? response(request, {'message': 'unavailable'}, 500)
            : metadataResponse(request);
      }
      return response(request, []);
    });
    await Supabase.initialize(
        url: 'https://example.test',
        anonKey: 'fixture-public-key',
        debug: false,
        authOptions: const FlutterAuthClientOptions(
            autoRefreshToken: false,
            detectSessionInUri: false,
            localStorage: EmptyLocalStorage()),
        httpClient: transport);
  });
  setUp(() async {
    signInId = me;
    setupComplete = true;
    communityAccepted = false;
    profile = savedProfile();
    writes = [];
    metadataWrites = 0;
    rejectLoad = false;
    failLogout = false;
    failMetadata = false;
    await signIn();
  });
  tearDown(() => AppColors.isDarkMode = true);
  tearDownAll(() async => Supabase.instance.dispose());

  Future<void> render(WidgetTester tester,
      {bool edit = false,
      double width = 390,
      double height = 1000,
      double textScale = 1,
      bool dark = true}) async {
    tester.view.physicalSize = Size(width, height);
    tester.view.devicePixelRatio = 1;
    AppColors.isDarkMode = dark;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    final router = GoRouter(initialLocation: '/setup', routes: [
      GoRoute(
          path: '/setup',
          builder: (_, __) => SetupScreen(
              forceEdit: edit,
              metadataService: AccountMetadataService(
                  client: Supabase.instance.client, httpClient: transport))),
      GoRoute(
          path: '/profile',
          builder: (_, __) =>
              const Scaffold(body: Text('Profile destination'))),
      GoRoute(
          path: '/feed',
          builder: (_, __) => const Scaffold(body: Text('Feed destination'))),
      GoRoute(
          path: '/auth',
          builder: (_, __) => const Scaffold(body: Text('Auth destination'))),
    ]);
    addTearDown(router.dispose);
    await tester.pumpWidget(ProviderScope(
        child: MaterialApp.router(
      routerConfig: router,
      theme: ThemeData(brightness: dark ? Brightness.dark : Brightness.light),
      builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(
              disableAnimations: true,
              textScaler: TextScaler.linear(textScale)),
          child: child!),
    )));
    await tester.pumpAndSettle();
  }

  Future<void> settle(WidgetTester tester) async {
    await tester.pumpAndSettle();
    // The shared auth client was initialized outside the widget's FakeAsync
    // zone. Let its real event loop finish before asserting navigation.
    for (var i = 0; i < 3; i++) {
      await tester.runAsync(() => Future<void>.delayed(Duration.zero));
      await tester.pumpAndSettle();
    }
  }

  Future<void> tapKey(WidgetTester tester, String key) async {
    final target = find.byKey(ValueKey(key));
    await tester.ensureVisible(target);
    await tester.pumpAndSettle();
    await tester.tap(target);
    await tester.pump();
  }

  GradientButton saveButton(WidgetTester tester) => tester
      .widget<GradientButton>(find.byKey(const ValueKey('setup-save')));

  for (final dark in [true, false]) {
    testWidgets(
        'existing user who only needs consent sees a consent-first state at 320px in ${dark ? 'night' : 'day'}',
        (tester) async {
      await render(tester, width: 320, height: 680, textScale: 1.5, dark: dark);
      expect(find.text('Дүрэм шинэчлэгдлээ'), findsOneWidget);
      expect(
          find.text(
              'Үргэлжлүүлэхийн өмнө 18+ болон хамтын орчны дүрмийг зөвшөөрнө үү.'),
          findsOneWidget);
      expect(find.text('Профайл засах'), findsNothing);
      expect(find.byType(GlassBack), findsNothing,
          reason: 'The router would only bounce a back press to /setup.');
      expect(find.byType(TextFormField), findsNothing,
          reason: 'Consent-only state hides the profile form.');
      final checkbox = find.byKey(const ValueKey('setup-community-agreement'));
      expect(checkbox, findsOneWidget);
      expect(tester.widget<CheckboxListTile>(checkbox).value, isFalse);
      expect(saveButton(tester).label, 'Зөвшөөрч үргэлжлүүлэх');
      expect(saveButton(tester).onPressed, isNotNull);
      final signOut = find.byKey(const ValueKey('setup-sign-out'));
      expect(signOut, findsOneWidget);
      expect(find.text('Гарах'), findsOneWidget);
      expect(tester.widget<TextButton>(signOut).onPressed, isNotNull);
      expect(find.text('Бүртгэл устгах'), findsOneWidget);
      // Consent card first, then the primary button, then sign out, then the
      // quiet delete link last.
      final card = tester.getTopLeft(checkbox).dy;
      final save = tester.getTopLeft(find.byKey(const ValueKey('setup-save')));
      final out = tester.getTopLeft(signOut).dy;
      final delete =
          tester.getTopLeft(find.byKey(const ValueKey('setup-delete-account')));
      expect(card, lessThan(save.dy));
      expect(save.dy, lessThan(out));
      expect(out, lessThan(delete.dy));
      final signOutSize =
          tester.getSize(find.byKey(const ValueKey('setup-sign-out')));
      expect(signOutSize.height, greaterThanOrEqualTo(44));
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets(
      'consent-only agreement records only the metadata, even for a legacy profile that fails validation',
      (tester) async {
    profile = {...savedProfile(), 'username': 'x'};
    await render(tester);
    await tapKey(tester, 'setup-save');
    await tester.pumpAndSettle();
    expect(metadataWrites, 0);
    expect(
        find.text(
            '18 нас хүрсэн бөгөөд хамтын орчны дүрмийг зөвшөөрч байгаагаа баталгаажуулна уу.'),
        findsOneWidget);

    await tapKey(tester, 'setup-community-agreement');
    await tapKey(tester, 'setup-save');
    await settle(tester);
    expect(writes, isEmpty);
    expect(metadataWrites, 1);
    expect(
        CommunityRules.isAccepted(
            Supabase.instance.client.auth.currentUser?.userMetadata),
        isTrue);
    expect(find.text('Feed destination'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('consent-only sign out ends the session and opens auth landing',
      (tester) async {
    await render(tester);
    await tapKey(tester, 'setup-sign-out');
    await settle(tester);
    expect(Supabase.instance.client.auth.currentUser, isNull);
    expect(find.text('Auth destination'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'consent-only sign out whose server call fails still leaves, without the account-changed view',
      (tester) async {
    failLogout = true;
    await render(tester);
    await tapKey(tester, 'setup-sign-out');
    await settle(tester);
    // The local session is gone even though the logout request failed.
    expect(Supabase.instance.client.auth.currentUser, isNull);
    expect(find.textContaining('Нэвтэрсэн бүртгэл өөрчлөгдлөө'), findsNothing);
    expect(find.text('Auth destination'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'consent-only agreement that fails to save shows the error and stays',
      (tester) async {
    failMetadata = true;
    await render(tester);
    await tapKey(tester, 'setup-community-agreement');
    await tapKey(tester, 'setup-save');
    await settle(tester);
    expect(metadataWrites, 1);
    expect(writes, isEmpty);
    expect(find.text('Хадгалахад алдаа гарлаа. Сүлжээгээ шалгана уу.'),
        findsOneWidget);
    expect(find.text('Дүрэм шинэчлэгдлээ'), findsOneWidget);
    expect(find.text('Feed destination'), findsNothing);
    expect(
        CommunityRules.isAccepted(
            Supabase.instance.client.auth.currentUser?.userMetadata),
        isFalse);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'consent-only state after a failed profile load still offers retry, consent and sign out',
      (tester) async {
    rejectLoad = true;
    await render(tester);
    expect(find.text('Дүрэм шинэчлэгдлээ'), findsOneWidget);
    expect(find.text('Дахин оролдох'), findsOneWidget);
    expect(find.byKey(const ValueKey('setup-community-agreement')),
        findsOneWidget);
    expect(saveButton(tester).onPressed, isNotNull);
    expect(
        tester
            .widget<TextButton>(find.byKey(const ValueKey('setup-sign-out')))
            .onPressed,
        isNotNull);
    expect(tester.takeException(), isNull);
  });

  testWidgets('profile edit opened from the profile keeps its title and back',
      (tester) async {
    communityAccepted = true;
    await signIn();
    await render(tester, edit: true);
    expect(find.text('Профайл засах'), findsOneWidget);
    expect(find.byType(GlassBack), findsOneWidget);
    expect(find.text('Дүрэм шинэчлэгдлээ'), findsNothing);
    expect(find.byKey(const ValueKey('setup-sign-out')), findsNothing);
    expect(find.byKey(const ValueKey('setup-community-agreement')),
        findsNothing);
    expect(find.byType(TextFormField), findsWidgets);
    expect(saveButton(tester).label, 'Хадгалах');
  });

  for (final dark in [true, false]) {
    testWidgets(
        'new user keeps the full create form with consent directly above save in ${dark ? 'night' : 'day'}',
        (tester) async {
      setupComplete = false;
      profile = null;
      await signIn();
      await render(tester, width: 320, height: 680, textScale: 1.5, dark: dark);
      expect(find.text('Өөрийгөө'), findsOneWidget);
      expect(find.text('Дүрэм шинэчлэгдлээ'), findsNothing);
      expect(find.byType(GlassBack), findsNothing);
      expect(find.byKey(const ValueKey('setup-sign-out')), findsNothing);
      expect(find.byType(TextFormField), findsWidgets);
      expect(saveButton(tester).label, 'Эхлэх');
      final checkbox = find.byKey(const ValueKey('setup-community-agreement'));
      expect(checkbox, findsOneWidget);
      final lastField = tester.getTopLeft(find.byType(TextFormField).last).dy;
      final card = tester.getTopLeft(checkbox).dy;
      final save =
          tester.getTopLeft(find.byKey(const ValueKey('setup-save'))).dy;
      expect(lastField, lessThan(card));
      expect(card, lessThan(save));
      expect(tester.takeException(), isNull);
    });
  }
}
