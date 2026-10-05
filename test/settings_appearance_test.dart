import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:night_owl_ub/core/theme/app_colors.dart';
import 'package:night_owl_ub/core/theme/theme_provider.dart';
import 'package:night_owl_ub/features/auth/providers/auth_provider.dart';
import 'package:night_owl_ub/features/profile/screens/settings_screen.dart';
import 'package:night_owl_ub/models/user_profile.dart';

class _SettingsFixture extends ConsumerWidget {
  const _SettingsFixture();

  @override
  Widget build(BuildContext context, WidgetRef ref) => MaterialApp(
      theme: ThemeData(brightness: Brightness.light),
      darkTheme: ThemeData(brightness: Brightness.dark),
      themeMode: ref.watch(themeModeProvider),
      builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(textScaler: const TextScaler.linear(2)),
          child: child!),
      home: const SettingsScreen());
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => GoogleFonts.config.allowRuntimeFetching = false);
  for (final initial in [ThemeMode.dark, ThemeMode.light]) {
    testWidgets(
        'Settings at 320px in ${initial.name} exposes and saves all modes',
        (tester) async {
      SharedPreferences.setMockInitialValues({'theme_mode': initial.name});
      tester.view.physicalSize = const Size(320, 900);
      tester.view.devicePixelRatio = 1;
      tester.platformDispatcher.platformBrightnessTestValue = Brightness.light;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.platformDispatcher.clearPlatformBrightnessTestValue);
      addTearDown(() => AppColors.isDarkMode = true);
      await tester.pumpWidget(ProviderScope(overrides: [
        sessionUserIdProvider.overrideWithValue(null),
        currentProfileProvider.overrideWith((_) async => UserProfile(
            id: 'fixture-profile',
            username: 'actual_person',
            name: 'Actual profile name',
            bio: 'The person’s saved profile biography')),
      ], child: const _SettingsFixture()));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.text('Actual profile name'), findsOneWidget);

      for (final choice in const [
        ('Өдөр', 'light', AppColors.bgBaseLight),
        ('Шөнө', 'dark', AppColors.bgBaseDark),
        ('Систем', 'system', AppColors.bgBaseLight),
      ]) {
        final target = find.text(choice.$1);
        await tester.scrollUntilVisible(target, 120,
            scrollable: find.byType(Scrollable).first);
        await tester.pumpAndSettle();
        await tester.ensureVisible(target);
        await tester.pumpAndSettle();
        await tester.tap(target);
        await tester.pumpAndSettle();
        final prefs = await SharedPreferences.getInstance();
        expect(prefs.getString('theme_mode'), choice.$2);
        expect(tester.widget<Scaffold>(find.byType(Scaffold)).backgroundColor,
            choice.$3);
        expect(tester.takeException(), isNull);
      }
      tester.platformDispatcher.platformBrightnessTestValue = Brightness.dark;
      await tester.pumpAndSettle();
      expect(tester.widget<Scaffold>(find.byType(Scaffold)).backgroundColor,
          AppColors.bgBaseDark);
      await tester.scrollUntilVisible(find.text('Actual profile name'), -120,
          scrollable: find.byType(Scrollable).first);
      await tester.pumpAndSettle();
      expect(find.text('Actual profile name'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    });
  }
}
