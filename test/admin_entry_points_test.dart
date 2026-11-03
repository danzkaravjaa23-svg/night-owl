import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:night_owl_ub/features/auth/providers/auth_provider.dart';
import 'package:night_owl_ub/features/profile/screens/settings_screen.dart';
import 'package:night_owl_ub/models/user_profile.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    GoogleFonts.config.allowRuntimeFetching = false;
  });

  test('admin entry affordance requires matching active account', () {
    final active = UserProfile.fromJson({
      'id': 'admin-a',
      'is_admin': true,
      'is_banned': false,
    });
    expect(active.canModerate('admin-a'), isTrue);
    expect(active.canModerate('admin-b'), isFalse);
    expect(active.canModerate(null), isFalse);
    expect(active.copyWith(isBanned: true).canModerate('admin-a'), isFalse);
    expect(active.copyWith(isAdmin: false).canModerate('admin-a'), isFalse);
    expect(
        UserProfile.fromJson({'id': 'member'}).canModerate('member'), isFalse);
    expect(
        UserProfile.fromJson(
                {'id': 'banned', 'is_admin': true, 'is_banned': true})
            .canModerate('banned'),
        isFalse);
    // Privilege flags never travel in the ordinary profile update payload.
    expect(active.toJson().keys, isNot(contains('is_admin')));
    expect(active.toJson().keys, isNot(contains('is_banned')));
  });

  for (final scenario in ['admin', 'member', 'banned', 'stale', 'signed-out']) {
    testWidgets('settings admin entry: $scenario', (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final router = GoRouter(initialLocation: '/settings', routes: [
        GoRoute(
            path: '/settings',
            builder: (context, state) => const SettingsScreen()),
        GoRoute(
            path: '/admin',
            builder: (context, state) =>
                const Scaffold(body: Text('Admin route reached'))),
      ]);
      addTearDown(router.dispose);
      await tester.pumpWidget(ProviderScope(overrides: [
        sessionUserIdProvider
            .overrideWithValue(scenario == 'signed-out' ? null : 'owner'),
        authUserProvider.overrideWith((_) => Stream.value(null)),
        currentProfileProvider.overrideWith((_) async => UserProfile(
              id: scenario == 'stale' ? 'previous-owner' : 'owner',
              username: 'fixture',
              isAdmin: scenario != 'member',
              isBanned: scenario == 'banned',
            )),
      ], child: MaterialApp.router(routerConfig: router)));
      await tester.pumpAndSettle();
      // Build the lazy settings rows before checking that the link is absent.
      await tester.scrollUntilVisible(find.text('Бизнес самбар'), 180,
          scrollable: find.byType(Scrollable).first);
      await tester.pumpAndSettle();
      expect(find.text('Админ панел'),
          scenario == 'admin' ? findsOneWidget : findsNothing);
      if (scenario == 'admin') {
        await tester.ensureVisible(find.text('Админ панел'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Админ панел'));
        await tester.pumpAndSettle();
        expect(find.text('Admin route reached'), findsOneWidget);
      }
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    });
  }
}
