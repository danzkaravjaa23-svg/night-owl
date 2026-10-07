import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:image/image.dart' as image;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:night_owl_ub/core/constants/avatar_presets.dart';
import 'package:night_owl_ub/core/theme/app_colors.dart';
import 'package:night_owl_ub/core/widgets/app_avatar.dart';
import 'package:night_owl_ub/core/widgets/gradient_button.dart';
import 'package:night_owl_ub/features/auth/screens/setup_screen.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const me = 'fixture-user';
  var signInId = me;
  var setupComplete = true;
  Map<String, dynamic>? profile;
  late List<Map<String, dynamic>> writes;
  late List<http.Request> uploads;
  var metadataWrites = 0;
  var rejectLoad = false;
  Future<http.Response> Function(http.Request)? saveReply;
  Future<http.Response> Function(http.Request)? uploadReply;
  http.Response response(http.Request request, Object? body,
          [int status = 200]) =>
      http.Response(jsonEncode(body), status,
          headers: {'content-type': 'application/json'}, request: request);
  Map<String, dynamic> user(String id) => {
        'id': id,
        'aud': 'authenticated',
        'created_at': '2026-10-07T00:00:00Z',
        'user_metadata': {'setup_complete': setupComplete},
      };
  Future<void> signIn([String id = me]) async {
    signInId = id;
    await Supabase.instance.client.auth.signInWithPassword(
        email: '$id@example.test', password: 'fixture-password');
  }

  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    signInId = me;
    profile = {
      'id': me,
      'username': 'fixture_user',
      'full_name': 'Fixture',
      'bio': 'Saved bio',
      'avatar_url': null,
      'interests': <String>[]
    };
    writes = [];
    uploads = [];
    metadataWrites = 0;
    rejectLoad = false;
    saveReply = null;
    uploadReply = null;
    await Supabase.initialize(
        url: 'https://example.test',
        anonKey: 'fixture-public-key',
        debug: false,
        authOptions: const FlutterAuthClientOptions(
            autoRefreshToken: false,
            detectSessionInUri: false,
            localStorage: EmptyLocalStorage()),
        httpClient: MockClient((request) async {
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
          if (path == '/rest/v1/profiles' && request.method == 'GET') {
            return rejectLoad
                ? response(
                    request, {'message': 'offline', 'code': 'XX000'}, 400)
                : response(request, profile == null ? [] : [profile]);
          }
          if (path == '/rest/v1/profiles' && request.method == 'POST') {
            writes.add(
                Map<String, dynamic>.from(jsonDecode(request.body) as Map));
            if (saveReply != null) return await saveReply!(request);
            return response(request, {});
          }
          if (path.startsWith('/storage/v1/object/avatars/')) {
            uploads.add(request);
            if (uploadReply != null) return await uploadReply!(request);
            return response(request, {'Key': path});
          }
          if (path == '/auth/v1/user' && request.method == 'PUT') {
            metadataWrites++;
            setupComplete = true;
            return response(request, user(signInId));
          }
          return response(request, []);
        }));
  });
  setUp(() async {
    signInId = me;
    setupComplete = true;
    profile = {
      'id': me,
      'username': 'fixture_user',
      'full_name': 'Fixture',
      'bio': 'Saved bio',
      'avatar_url': null,
      'interests': <String>[]
    };
    writes = [];
    uploads = [];
    metadataWrites = 0;
    rejectLoad = false;
    saveReply = null;
    uploadReply = null;
    await signIn();
  });
  tearDown(() => AppColors.isDarkMode = true);
  tearDownAll(() async => Supabase.instance.dispose());

  Future<void> render(WidgetTester tester,
      {bool edit = true,
      Future<Uint8List?> Function()? picker,
      double width = 390,
      double textScale = 1,
      bool dark = true}) async {
    tester.view.physicalSize = Size(width, 1000);
    tester.view.devicePixelRatio = 1;
    AppColors.isDarkMode = dark;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    final router = GoRouter(initialLocation: '/setup', routes: [
      GoRoute(
          path: '/setup',
          builder: (_, __) =>
              SetupScreen(forceEdit: edit, avatarPicker: picker)),
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

  AppAvatar preview(WidgetTester tester) => tester
      .widget<AppAvatar>(find.byKey(const ValueKey('setup-avatar-preview')));
  Future<void> select(WidgetTester tester, NightOwlAvatarPreset preset) async {
    final target = find.byKey(ValueKey('avatar-preset-${preset.id}'));
    await tester.ensureVisible(target);
    await tester.pumpAndSettle();
    await tester.tap(target);
    await tester.pump();
  }

  Future<void> choosePhoto(WidgetTester tester) async {
    final target = find.byKey(const ValueKey('setup-upload-avatar'));
    await tester.ensureVisible(target);
    await tester.pumpAndSettle();
    await tester.tap(target);
    await tester.pumpAndSettle();
  }

  Future<void> save(WidgetTester tester) async {
    final target = find.byKey(const ValueKey('setup-save'));
    await tester.ensureVisible(target);
    await tester.pumpAndSettle();
    await tester.tap(target);
    await tester.pump();
  }

  Future<void> flushUpload(WidgetTester tester) async {
    // Native JPEG compression uses an isolate; allow its real event loop to
    // finish without waiting for a deliberately held upload/server response.
    for (var i = 0; i < 40 && uploads.isEmpty; i++) {
      await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 10)));
      await tester.pump();
    }
  }

  Uint8List photo() =>
      Uint8List.fromList(image.encodePng(image.Image(width: 2, height: 2)));

  for (final preset in NightOwlAvatars.all) {
    testWidgets(
        'explicit ${preset.id} choice previews and persists without uploading',
        (tester) async {
      await render(tester);
      await select(tester, preset);
      expect(preview(tester).imageUrl, preset.value);
      await save(tester);
      await tester.pumpAndSettle();
      expect(writes.single['avatar_url'], preset.value);
      expect(writes.single['id'], me);
      expect(uploads, isEmpty);
      expect(metadataWrites, 0,
          reason:
              'Editing an already completed profile needs no auth mutation.');
      expect(find.text('Profile destination'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }
  testWidgets(
      'new empty profile persists the default owl with no inferred demographic fields',
      (tester) async {
    profile = null;
    setupComplete = false;
    await signIn();
    await render(tester, edit: false);
    expect(preview(tester).imageUrl, NightOwlAvatars.defaultPreset.value);
    final username = find.byType(TextFormField).at(1);
    await tester.ensureVisible(username);
    await tester.enterText(username, 'new_user');
    await save(tester);
    await tester.pumpAndSettle();
    expect(writes.single['avatar_url'], NightOwlAvatars.defaultPreset.value);
    expect(writes.single.keys, isNot(contains('gender')));
    expect(writes.single.keys, isNot(contains('age')));
    expect(find.text('Feed destination'), findsOneWidget);
    expect(metadataWrites, 1);
    expect(
        Supabase
            .instance.client.auth.currentUser?.userMetadata?['setup_complete'],
        isTrue);
  });
  testWidgets('existing photo and cancelled photo picker remain unchanged',
      (tester) async {
    const url = 'https://media.test/existing.jpg';
    profile!['avatar_url'] = url;
    await render(tester, picker: () async => null);
    expect(preview(tester).imageUrl, url);
    await choosePhoto(tester);
    expect(preview(tester).imageUrl, url);
    await save(tester);
    await tester.pumpAndSettle();
    expect(writes.single.containsKey('avatar_url'), isFalse);
    expect(uploads, isEmpty);
  });
  testWidgets('preset remains selected when photo picker is cancelled',
      (tester) async {
    await render(tester, picker: () async => null);
    final preset = NightOwlAvatars.all.last;
    await select(tester, preset);
    await choosePhoto(tester);
    expect(preview(tester).imageUrl, preset.value);
    await save(tester);
    await tester.pumpAndSettle();
    expect(writes.single['avatar_url'], preset.value);
  });
  testWidgets('own photo uploads as JPEG and its URL replaces the selected owl',
      (tester) async {
    await render(tester, picker: () async => photo());
    await choosePhoto(tester);
    expect(find.byKey(const ValueKey('setup-upload-preview')), findsOneWidget);
    await save(tester);
    await flushUpload(tester);
    await tester.pumpAndSettle();
    expect(uploads, hasLength(1));
    expect(uploads.single.headers['content-type'],
        startsWith('multipart/form-data'));
    final multipart = uploads.single.bodyBytes;
    expect(latin1.decode(multipart).toLowerCase(),
        contains('content-type: image/jpeg'));
    final jpegStart = List.generate(multipart.length - 1, (i) => i)
        .firstWhere((i) => multipart[i] == 0xff && multipart[i + 1] == 0xd8);
    expect(image.decodeJpg(multipart.sublist(jpegStart)), isNotNull);
    expect(
        writes.single['avatar_url'],
        startsWith(
            'https://example.test/storage/v1/object/public/avatars/$me/avatar_'));
    expect(find.text('Profile destination'), findsOneWidget);
  });
  testWidgets(
      'failed save keeps choice and a second press cannot duplicate an in-flight save',
      (tester) async {
    final pending = Completer<http.Response>();
    http.Request? held;
    saveReply = (request) {
      held = request;
      return pending.future;
    };
    await render(tester);
    final preset = NightOwlAvatars.all[1];
    await select(tester, preset);
    final target = find.byKey(const ValueKey('setup-save'));
    await tester.ensureVisible(target);
    await tester.pumpAndSettle();
    final submit = tester.widget<GradientButton>(target).onPressed!;
    submit();
    submit();
    await tester.pump();
    expect(writes, hasLength(1));
    pending.complete(
        response(held!, {'message': 'write failed', 'code': 'XX000'}, 400));
    await tester.pumpAndSettle();
    expect(preview(tester).imageUrl, preset.value);
    expect(find.text('Хадгалахад алдаа гарлаа. Дахин оролдоно уу.'),
        findsOneWidget);
    saveReply = null;
    await save(tester);
    await tester.pumpAndSettle();
    expect(writes, hasLength(2));
    expect(writes.last['avatar_url'], preset.value);
  });
  testWidgets(
      'account switch during upload cannot save old profile to a new account',
      (tester) async {
    final pending = Completer<http.Response>();
    http.Request? held;
    uploadReply = (request) {
      held = request;
      return pending.future;
    };
    await render(tester, picker: () async => photo());
    await choosePhoto(tester);
    await save(tester);
    await flushUpload(tester);
    expect(held, isNotNull);
    await signIn('another-user');
    await tester.pump();
    pending.complete(response(held!, {'Key': held!.url.path}));
    await tester.pumpAndSettle();
    expect(writes, isEmpty);
    expect(metadataWrites, 0);
    expect(
        find.text('Нэвтэрсэн бүртгэл өөрчлөгдлөө. Профайлаа дахин нээгээрэй.'),
        findsOneWidget);
  });
  testWidgets('late profile save cannot update the new account auth metadata',
      (tester) async {
    final pending = Completer<http.Response>();
    http.Request? held;
    saveReply = (request) {
      held = request;
      return pending.future;
    };
    await render(tester);
    await save(tester);
    expect(writes.single['id'], me);
    await signIn('another-user');
    await tester.pump();
    pending.complete(response(held!, {}));
    await tester.pumpAndSettle();
    expect(metadataWrites, 0);
    expect(find.text('Profile destination'), findsNothing);
  });
  testWidgets('profile read failure disables save until a successful retry',
      (tester) async {
    rejectLoad = true;
    await render(tester);
    expect(
        tester
            .widget<GradientButton>(find.byKey(const ValueKey('setup-save')))
            .onPressed,
        isNull);
    rejectLoad = false;
    await tester.tap(find.text('Дахин оролдох'));
    await tester.pumpAndSettle();
    expect(
        tester
            .widget<GradientButton>(find.byKey(const ValueKey('setup-save')))
            .onPressed,
        isNotNull);
  });
  for (final dark in [true, false]) {
    testWidgets(
        'avatar choices fit 320px with large text in ${dark ? 'night' : 'day'} theme',
        (tester) async {
      await render(tester, width: 320, textScale: 1.5, dark: dark);
      await select(tester, NightOwlAvatars.all.last);
      expect(tester.takeException(), isNull);
      expect(preview(tester).imageUrl, NightOwlAvatars.all.last.value);
    });
  }
}
