import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:night_owl_ub/core/router/app_router.dart';
import 'package:night_owl_ub/core/utils/validators.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Exercises the same legacy route redirects without initializing Supabase,
/// sending a request, or opening an external sharing/payment service.
GoRouter _compatibilityRouter(String initialLocation) => GoRouter(
  initialLocation: initialLocation,
  routes: [
    GoRoute(path: AppRoutes.feed,
      builder: (_, __) => const Scaffold(body: Text('Free feed'))),
    GoRoute(path: AppRoutes.postDetail,
      builder: (_, state) => Scaffold(body: Text(
        'Post content: ${state.pathParameters['id']}',
        key: const Key('post-content')))),
    GoRoute(path: '/qpay',
      redirect: (_, state) => AppRoutes.freeReleaseDestination(state.uri)),
    GoRoute(path: AppRoutes.qpay,
      redirect: (_, state) => AppRoutes.freeReleaseDestination(state.uri)),
    GoRoute(path: AppRoutes.affiliateUnlock,
      redirect: (_, state) => AppRoutes.freeReleaseDestination(state.uri)),
    GoRoute(path: AppRoutes.affiliate,
      redirect: (_, state) => AppRoutes.freeReleaseDestination(state.uri)),
    GoRoute(path: AppRoutes.invite,
      builder: (_, __) => const Scaffold(body: Text('Free invitation'))),
  ],
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Free release compatibility', () {
    test('old payment links open content and discard payment arguments', () {
      final destination = AppRoutes.freeReleaseDestination(Uri.parse(
        '/qpay/post-123?amount=50000&bank=example&invoice=old#payment'));
      expect(destination, '/post/post-123');
      final uri = Uri.parse(destination!);
      expect(uri.queryParameters, isEmpty);
      expect(uri.fragment, isEmpty);
      expect(AppRoutes.freeReleaseDestination(Uri.parse('/qpay?amount=50000')),
        AppRoutes.feed);
    });

    test('encoded content ids remain a single id rather than injected routes', () {
      for (final id in ['post/other', 'post?amount=1&paid=true',
          'post#payment', 'post%2Fother', 'пост 123']) {
        final source = Uri.parse('/qpay/${Uri.encodeComponent(id)}?amount=1');
        final destination = Uri.parse(AppRoutes.freeReleaseDestination(source)!);
        expect(destination.pathSegments, ['post', id], reason: id);
        expect(destination.queryParameters, isEmpty, reason: id);
        expect(destination.fragment, isEmpty, reason: id);
      }
    });

    test('affiliate aliases lead to free invitation without unlock arguments', () {
      for (final path in [AppRoutes.affiliate, AppRoutes.affiliateUnlock]) {
        expect(AppRoutes.freeReleaseDestination(Uri.parse('$path?unlocked=false&amount=1')),
          AppRoutes.invite);
      }
    });

    test('ordinary app and auth routes retain their own behavior', () {
      for (final path in ['/', '/auth', '/auth/login?next=/feed', '/auth/setup',
          '/feed', '/post/post-123?note=hello', '/profile', '/invite',
          '/affiliate/unlock-extra', '/qpay/a/b', '/notqpay/a']) {
        expect(AppRoutes.freeReleaseDestination(Uri.parse(path)), isNull,
          reason: path);
      }
    });

    testWidgets('a legacy payment URL navigates to post content without checkout',
      (tester) async {
        final router = _compatibilityRouter(
          '/qpay/post-123?amount=50000&invoice=old');
        addTearDown(router.dispose);
        await tester.pumpWidget(MaterialApp.router(routerConfig: router));
        await tester.pumpAndSettle();
        expect(find.text('Post content: post-123'), findsOneWidget);
        expect(router.routeInformationProvider.value.uri.toString(), '/post/post-123');
        expect(tester.takeException(), isNull);

        router.go('/qpay?amount=50000');
        await tester.pumpAndSettle();
        expect(find.text('Free feed'), findsOneWidget);
        expect(router.routeInformationProvider.value.uri.path, AppRoutes.feed);
        expect(tester.takeException(), isNull);
      });

    testWidgets('legacy routes preserve a special-character content id',
      (tester) async {
        const id = 'post/other?paid=true#payment';
        final router = _compatibilityRouter(
          '/qpay/${Uri.encodeComponent(id)}?amount=50000');
        addTearDown(router.dispose);
        await tester.pumpWidget(MaterialApp.router(routerConfig: router));
        await tester.pumpAndSettle();
        expect(find.text('Post content: $id'), findsOneWidget);
        final destination = router.routeInformationProvider.value.uri;
        expect(destination.pathSegments, ['post', id]);
        expect(destination.queryParameters, isEmpty);
        expect(destination.fragment, isEmpty);
        expect(tester.takeException(), isNull);
      });

    testWidgets('invitation aliases ignore absent and old local unlock flags',
      (tester) async {
        SharedPreferences.setMockInitialValues({});
        final router = _compatibilityRouter(AppRoutes.affiliateUnlock);
        addTearDown(router.dispose);
        await tester.pumpWidget(MaterialApp.router(routerConfig: router));
        await tester.pumpAndSettle();
        expect(find.text('Free invitation'), findsOneWidget);
        expect(router.routeInformationProvider.value.uri.path, AppRoutes.invite);
        final prefs = await SharedPreferences.getInstance();
        expect(prefs.containsKey('affiliate_unlocked'), isFalse);

        for (final oldFlag in [false, true]) {
          await prefs.setBool('affiliate_unlocked', oldFlag);
          for (final alias in [AppRoutes.affiliate, AppRoutes.affiliateUnlock]) {
            router.go('$alias?amount=50000');
            await tester.pumpAndSettle();
            expect(find.text('Free invitation'), findsOneWidget);
            expect(router.routeInformationProvider.value.uri.toString(), AppRoutes.invite);
            expect(prefs.getBool('affiliate_unlocked'), oldFlag);
            expect(tester.takeException(), isNull);
          }
        }
      });
  });

  test('admission price refuses malformed amounts instead of making them free', () {
    for (final input in <String?>[null, '', '   ', '0', '12000', ' 12000 ', '2147483647']) {
      expect(Validators.admissionPrice(input), isNull, reason: '$input');
    }
    for (final input in ['-1', 'free', '12.50', '0x10', '2147483648', '1,000']) {
      expect(Validators.admissionPrice(input), isNotNull, reason: input);
    }
  });
}
