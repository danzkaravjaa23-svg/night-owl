import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:night_owl_ub/core/theme/app_colors.dart';
import 'package:night_owl_ub/core/theme/theme_provider.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  tearDown(() => AppColors.isDarkMode = true);

  test('a choice made during startup wins over the delayed saved mode',
      () async {
    final loaded = Completer<String?>();
    final writes = <String>[];
    final notifier = ThemeModeNotifier(
        readMode: () => loaded.future,
        writeMode: (mode) async {
          writes.add(mode);
          return true;
        });
    addTearDown(notifier.dispose);
    final change = notifier.setMode(ThemeMode.light);
    expect(notifier.state, ThemeMode.light);
    loaded.complete('dark');
    await change;
    expect(notifier.state, ThemeMode.light);
    expect(AppColors.isDarkMode, isFalse);
    expect(writes, ['light']);
  });

  test('rapid choices are persisted in order with the latest choice last',
      () async {
    final firstWrite = Completer<bool>();
    final writes = <String>[];
    final notifier = ThemeModeNotifier(
        readMode: () async => 'dark',
        writeMode: (mode) {
          writes.add(mode);
          return writes.length == 1 ? firstWrite.future : Future.value(true);
        });
    addTearDown(notifier.dispose);
    await notifier.ready;
    final first = notifier.setMode(ThemeMode.light);
    final latest = notifier.setMode(ThemeMode.system);
    await Future<void>.delayed(Duration.zero);
    expect(writes, ['light']);
    expect(notifier.state, ThemeMode.system);
    firstWrite.complete(true);
    await Future.wait([first, latest]);
    expect(writes, ['light', 'system']);
    expect(notifier.state, ThemeMode.system);
  });

  test('a false save result reports failure and restores the stored choice',
      () async {
    var saved = 'light';
    final notifier = ThemeModeNotifier(
        readMode: () async => saved,
        writeMode: (mode) async {
          saved = mode;
          return mode != 'dark';
        });
    addTearDown(notifier.dispose);
    await notifier.ready;
    await expectLater(notifier.setMode(ThemeMode.dark), throwsStateError);
    expect(notifier.state, ThemeMode.light);
    expect(AppColors.isDarkMode, isFalse);
    expect(saved, 'light');
  });

  test('a thrown save error reports failure and restores the stored choice',
      () async {
    final notifier = ThemeModeNotifier(
        readMode: () async => 'dark',
        writeMode: (_) async => throw StateError('storage unavailable'));
    addTearDown(notifier.dispose);
    await notifier.ready;
    await expectLater(notifier.setMode(ThemeMode.light), throwsStateError);
    expect(notifier.state, ThemeMode.dark);
    expect(AppColors.isDarkMode, isTrue);
  });

  test('an older failed save does not roll back a newer successful choice',
      () async {
    final firstWrite = Completer<bool>();
    var writes = 0;
    final notifier = ThemeModeNotifier(
        readMode: () async => 'dark',
        writeMode: (_) =>
            ++writes == 1 ? firstWrite.future : Future.value(true));
    addTearDown(notifier.dispose);
    await notifier.ready;
    final firstFailure =
        expectLater(notifier.setMode(ThemeMode.light), throwsStateError);
    final latest = notifier.setMode(ThemeMode.system);
    await Future<void>.delayed(Duration.zero);
    firstWrite.complete(false);
    await Future.wait([firstFailure, latest]);
    expect(notifier.state, ThemeMode.system);
    expect(writes, 3);
  });

  test('a latest failed save rolls back to the last successful queued save',
      () async {
    final firstWrite = Completer<bool>();
    var writes = 0;
    final notifier = ThemeModeNotifier(
        readMode: () async => 'dark',
        writeMode: (_) =>
            ++writes == 1 ? firstWrite.future : Future.value(false));
    addTearDown(notifier.dispose);
    await notifier.ready;
    final first = notifier.setMode(ThemeMode.light);
    final latestFailure =
        expectLater(notifier.setMode(ThemeMode.dark), throwsStateError);
    await Future<void>.delayed(Duration.zero);
    firstWrite.complete(true);
    await Future.wait([first, latestFailure]);
    expect(notifier.state, ThemeMode.light);
    expect(AppColors.isDarkMode, isFalse);
  });

  test('failed startup read keeps night default and allows a later save',
      () async {
    final notifier = ThemeModeNotifier(
        readMode: () async => throw StateError('storage unavailable'),
        writeMode: (_) async => true);
    addTearDown(notifier.dispose);
    await notifier.ready;
    expect(notifier.state, ThemeMode.dark);
    await notifier.setMode(ThemeMode.light);
    expect(notifier.state, ThemeMode.light);
  });

  test('a disposed notifier ignores delayed startup and rejects new changes',
      () async {
    final loaded = Completer<String?>();
    var writes = 0;
    final notifier = ThemeModeNotifier(
        readMode: () => loaded.future,
        writeMode: (_) async {
          writes++;
          return true;
        });
    notifier.dispose();
    AppColors.isDarkMode = false;
    loaded.complete('dark');
    await notifier.ready;
    expect(AppColors.isDarkMode, isFalse);
    await expectLater(notifier.setMode(ThemeMode.dark), throwsStateError);
    expect(writes, 0);
  });

  test('disposal during a save prevents failure rollback from changing colors',
      () async {
    final write = Completer<bool>();
    final notifier = ThemeModeNotifier(
        readMode: () async => 'dark', writeMode: (_) => write.future);
    await notifier.ready;
    final failure =
        expectLater(notifier.setMode(ThemeMode.light), throwsStateError);
    await Future<void>.delayed(Duration.zero);
    notifier.dispose();
    AppColors.isDarkMode = false;
    write.complete(false);
    await failure;
    expect(AppColors.isDarkMode, isFalse);
  });

  testWidgets(
      'System follows platform brightness while an explicit mode stays fixed',
      (tester) async {
    tester.platformDispatcher.platformBrightnessTestValue = Brightness.light;
    addTearDown(tester.platformDispatcher.clearPlatformBrightnessTestValue);
    final notifier = ThemeModeNotifier(
        readMode: () async => 'system', writeMode: (_) async => true);
    addTearDown(notifier.dispose);
    await notifier.ready;
    expect(notifier.state, ThemeMode.system);
    expect(AppColors.isDarkMode, isFalse);
    tester.platformDispatcher.platformBrightnessTestValue = Brightness.dark;
    await tester.pump();
    expect(AppColors.isDarkMode, isTrue);
    await notifier.setMode(ThemeMode.light);
    tester.platformDispatcher.platformBrightnessTestValue = Brightness.dark;
    await tester.pump();
    expect(notifier.state, ThemeMode.light);
    expect(AppColors.isDarkMode, isFalse);
  });
}
