import 'dart:async';
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
import 'package:night_owl_ub/features/discovery/services/discovery_service.dart';
import 'package:night_owl_ub/features/profile/screens/follow_list_screen.dart';

const _me = '00000000-0000-4000-8000-000000000001';
const _target = '00000000-0000-4000-8000-000000000002';
http.Response _response(http.Request request, Object? body,
        [int status = 200]) =>
    http.Response(jsonEncode(body), status,
        request: request,
        headers: {'content-type': 'application/json; charset=utf-8'});
Map<String, Object?> _person(String username, [String id = _target]) => {
      'profiles': {
        'id': id,
        'username': username,
        'full_name': 'Profile name',
        'avatar_url': null,
        'is_verified': true
      },
    };
Map<String, Object?> _session(String id) => {
      'access_token': 'fixture.${base64Url.encode(utf8.encode(jsonEncode({
                'sub': id,
                'exp': DateTime.now().millisecondsSinceEpoch ~/ 1000 + 3600,
              }))).replaceAll('=', '')}.fixture',
      'refresh_token': 'fixture-refresh',
      'token_type': 'bearer',
      'expires_in': 3600,
      'user': {
        'id': id,
        'aud': 'authenticated',
        'created_at': '2026-11-03T00:00:00Z'
      },
    };

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Future<http.Response?> Function(http.Request) intercept;
  var requested = false;
  var following = false;
  var signedInUser = _me;
  final changes = <bool>[];
  late ProviderContainer container;

  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    GoogleFonts.config.allowRuntimeFetching = false;
    intercept = (_) async => null;
    await Supabase.initialize(
        url: 'https://fixture.example.test',
        anonKey: 'fixture-public-key',
        debug: false,
        authOptions: const FlutterAuthClientOptions(
            autoRefreshToken: false,
            detectSessionInUri: false,
            localStorage: EmptyLocalStorage()),
        httpClient: MockClient((request) async {
          if (request.url.path == '/auth/v1/token') {
            return _response(request, _session(signedInUser));
          }
          final overridden = await intercept(request);
          if (overridden != null) return overridden;
          final select = request.url.queryParameters['select'] ?? '';
          if (request.url.path == '/rest/v1/rpc/set_follow') {
            final value = (jsonDecode(request.body) as Map)['p_follow'] == true;
            changes.add(value);
            requested = value;
            return _response(request, value ? 'requested' : 'none');
          }
          expect(request.method, 'GET',
              reason: 'Only mocked follow changes are permitted');
          if (request.url.path == '/rest/v1/follow_requests') {
            return _response(
                request,
                requested
                    ? [
                        {'target_id': _target}
                      ]
                    : []);
          }
          if (select.contains('profiles!follower_id')) {
            return _response(request, [_person('follower_profile')]);
          }
          if (select.contains('profiles!following_id')) {
            return _response(request, [_person('following_profile')]);
          }
          if (select == 'following_id') {
            return _response(
                request,
                following
                    ? [
                        {'following_id': _target}
                      ]
                    : []);
          }
          return _response(request, []);
        }));
  });
  tearDownAll(() => Supabase.instance.dispose());
  setUp(() async {
    intercept = (_) async => null;
    requested = false;
    following = false;
    changes.clear();
    signedInUser = _me;
    await Supabase.instance.client.auth.signInWithPassword(
        email: 'fixture@example.test', password: 'fixture-only');
  });

  Future<void> render(WidgetTester tester,
      {double scale = 1,
      Brightness brightness = Brightness.dark,
      String user = _me}) async {
    AppColors.isDarkMode = brightness == Brightness.dark;
    tester.view.physicalSize = const Size(320, 720);
    tester.view.devicePixelRatio = 1;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
      AppColors.isDarkMode = true;
    });
    container = ProviderContainer();
    addTearDown(container.dispose);
    await tester.pumpWidget(UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
            theme: ThemeData(brightness: brightness),
            builder: (context, child) => MediaQuery(
                data: MediaQuery.of(context).copyWith(
                    textScaler: TextScaler.linear(scale),
                    disableAnimations: true),
                child: child!),
            home: FollowListScreen(userId: user))));
    await tester.pumpAndSettle();
  }

  testWidgets(
      'switching tabs hides old people during loading and failure; retry recovers',
      (tester) async {
    await render(tester);
    expect(find.text('follower_profile'), findsOneWidget);
    final pending = Completer<http.Response>();
    http.Request? held;
    intercept = (request) async {
      if ((request.url.queryParameters['select'] ?? '')
          .contains('profiles!following_id')) {
        held = request;
        return pending.future;
      }
      return null;
    };
    await tester.tap(find.text('Дагаж буй'));
    await tester.pump();
    expect(find.text('follower_profile'), findsNothing);
    expect(find.text('Дагаж буй хүмүүсийг ачаалж байна'), findsOneWidget);
    pending.complete(_response(held!, {'message': 'fixture failure'}, 403));
    await tester.pumpAndSettle();
    expect(find.text('Ачаалж чадсангүй'), findsOneWidget);
    expect(find.text('follower_profile'), findsNothing);
    intercept = (_) async => null;
    await tester.tap(find.text('Дахин оролдох'));
    await tester.pumpAndSettle();
    expect(find.text('following_profile'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a late tab response cannot replace the selected list',
      (tester) async {
    await render(tester);
    final pending = Completer<http.Response>();
    http.Request? held;
    intercept = (request) async {
      if ((request.url.queryParameters['select'] ?? '')
          .contains('profiles!following_id')) {
        held = request;
        return pending.future;
      }
      return null;
    };
    await tester.tap(find.text('Дагаж буй'));
    await tester.pump();
    await tester.tap(find.text('Дагагч'));
    await tester.pumpAndSettle();
    expect(find.text('follower_profile'), findsOneWidget);
    pending.complete(_response(held!, [_person('late_wrong_tab')]));
    await tester.pumpAndSettle();
    expect(find.text('follower_profile'), findsOneWidget);
    expect(find.text('late_wrong_tab'), findsNothing);
  });

  testWidgets(
      'failed refresh keeps current-tab people with a visible retry notice',
      (tester) async {
    await render(tester);
    intercept = (request) async => (request.url.queryParameters['select'] ?? '')
            .contains('profiles!follower_id')
        ? _response(request, {'message': 'fixture failure'}, 403)
        : null;
    await tester
        .widget<RefreshIndicator>(find.byType(RefreshIndicator))
        .onRefresh();
    await tester.pumpAndSettle();
    expect(find.text('follower_profile'), findsOneWidget);
    expect(
        find.text(
            'Жагсаалтыг шинэчилж чадсангүй. Өмнөх мэдээллийг харуулж байна.'),
        findsOneWidget);
    intercept = (_) async => null;
    await tester.tap(find.text('Дахин оролдох'));
    await tester.pumpAndSettle();
    expect(
        find.text(
            'Жагсаалтыг шинэчилж чадсангүй. Өмнөх мэдээллийг харуулж байна.'),
        findsNothing);
  });

  testWidgets(
      'private follow is pending, can be cancelled, and refreshes social caches',
      (tester) async {
    await render(tester);
    expect(container.read(socialVersionProvider), 0);
    await tester.tap(find.text('Дагах'));
    await tester.pumpAndSettle();
    expect(changes, [true]);
    expect(find.text('Хүсэлттэй'), findsOneWidget);
    expect(find.text('Дагасан'), findsNothing);
    expect(container.read(socialVersionProvider), 1);
    await tester.tap(find.text('Хүсэлттэй'));
    await tester.pumpAndSettle();
    expect(changes, [true, false]);
    expect(find.text('Дагах'), findsOneWidget);
    expect(container.read(socialVersionProvider), 2);
  });

  testWidgets(
      'existing pending request loads accurately; failed cancel retains state',
      (tester) async {
    requested = true;
    await render(tester);
    expect(find.text('Хүсэлттэй'), findsOneWidget);
    intercept = (request) async => request.url.path.endsWith('/set_follow')
        ? _response(request, {'message': 'fixture failure'}, 403)
        : null;
    await tester.tap(find.text('Хүсэлттэй'));
    await tester.pumpAndSettle();
    expect(find.text('Хүсэлттэй'), findsOneWidget);
    expect(find.text('Үйлдэл амжилтгүй, дахин оролдоно уу'), findsOneWidget);
    expect(container.read(socialVersionProvider), 0);
  });

  testWidgets(
      'follow completion supersedes a pending tab load and duplicate taps',
      (tester) async {
    await render(tester);
    final mutation = Completer<http.Response>();
    final staleList = Completer<http.Response>();
    http.Request? mutationRequest;
    http.Request? listRequest;
    var mutations = 0;
    intercept = (request) async {
      if (request.url.path.endsWith('/set_follow')) {
        mutations++;
        mutationRequest = request;
        return mutation.future;
      }
      if (listRequest == null &&
          (request.url.queryParameters['select'] ?? '')
              .contains('profiles!following_id')) {
        listRequest = request;
        return staleList.future;
      }
      return null;
    };
    await tester.tap(find.text('Дагах'));
    await tester.tap(find.text('Дагах'));
    await tester.pump();
    expect(mutations, 1);
    await tester.tap(find.text('Дагаж буй'));
    await tester.pump();
    requested = true;
    mutation.complete(_response(mutationRequest!, 'requested'));
    await tester.pumpAndSettle();
    expect(find.text('following_profile'), findsOneWidget);
    expect(find.text('Хүсэлттэй'), findsOneWidget);
    staleList.complete(_response(listRequest!, [_person('stale_snapshot')]));
    await tester.pumpAndSettle();
    expect(find.text('stale_snapshot'), findsNothing);
    expect(find.text('Хүсэлттэй'), findsOneWidget);
  });

  testWidgets('a late follow response cannot update another signed-in account',
      (tester) async {
    await render(tester);
    final pending = Completer<http.Response>();
    http.Request? held;
    intercept = (request) async {
      if (request.url.path.endsWith('/set_follow')) {
        held = request;
        return pending.future;
      }
      return null;
    };
    await tester.tap(find.text('Дагах'));
    await tester.pump();
    signedInUser = '00000000-0000-4000-8000-000000000003';
    await Supabase.instance.client.auth.signInWithPassword(
        email: 'second-fixture@example.test', password: 'fixture-only');
    await tester.pumpAndSettle();
    pending.complete(_response(held!, 'requested'));
    await tester.pumpAndSettle();
    expect(find.text('Дагах'), findsOneWidget);
    expect(find.text('Хүсэлттэй'), findsNothing);
    expect(container.read(socialVersionProvider), 0);
  });

  for (final brightness in [Brightness.dark, Brightness.light]) {
    testWidgets(
        'people actions fit 320px at 2x text in $brightness and expose selected tabs',
        (tester) async {
      requested = true;
      final handle = tester.ensureSemantics();
      await render(tester, scale: 2, brightness: brightness);
      expect(tester.takeException(), isNull);
      final follow = find.widgetWithText(TextButton, 'Хүсэлттэй');
      expect(tester.getSize(follow).height, greaterThanOrEqualTo(44));
      expect(tester.getSize(find.byTooltip('Буцах')).height,
          greaterThanOrEqualTo(44));
      expect(
          tester.getSemantics(find.text('Дагагч')),
          matchesSemantics(
              label: 'Дагагч',
              isButton: true,
              isEnabled: true,
              hasEnabledState: true,
              isSelected: true,
              hasSelectedState: true,
              hasTapAction: true,
              hasFocusAction: true,
              isFocusable: true));
      await tester.tap(find.text('Дагаж буй'));
      await tester.pumpAndSettle();
      expect(find.text('following_profile'), findsOneWidget);
      expect(tester.takeException(), isNull);
      handle.dispose();
    });
  }
}
