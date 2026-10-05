import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:night_owl_ub/core/providers/user_settings_provider.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));
  test('notification settings persist for one account and do not leak to another', () async {
    final first = UserSettingsNotifier('first');
    await first.ready;
    await first.setNotifications(false);
    first.dispose();
    final restored = UserSettingsNotifier('first');
    final other = UserSettingsNotifier('other');
    await Future.wait([restored.ready, other.ready]);
    expect(restored.state.notifications, isFalse);
    expect(other.state.notifications, isTrue);
    restored.dispose(); other.dispose();
  });
  test('disabling presence persists before clearing the public timestamp', () async {
    var cleared = false;
    final settings = UserSettingsNotifier('user', clearPresence: () async {
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getBool('user_settings.user.activity'), isFalse);
      cleared = true;
    });
    await settings.setActivity(false);
    expect(cleared, isTrue);
    expect(settings.state.activity, isFalse);
    settings.dispose();
  });
  test('server failures roll back the privacy toggle and persisted value', () async {
    final settings = UserSettingsNotifier('user', clearPresence: () async => throw StateError('offline'));
    await settings.ready;
    await expectLater(settings.setActivity(false), throwsStateError);
    expect(settings.state.activity, isTrue);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getBool('user_settings.user.activity'), isTrue);
    settings.dispose();
  });
}
