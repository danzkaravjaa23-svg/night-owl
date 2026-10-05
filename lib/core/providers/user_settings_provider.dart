import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/supabase_service.dart';
import '../../features/auth/providers/auth_provider.dart';

class UserSettings {
  final bool loaded;
  final bool notifications;
  final bool activity;
  const UserSettings({this.loaded = false, this.notifications = true, this.activity = true});
}

/// Device preferences are scoped to the signed-in account, including failures.
class UserSettingsNotifier extends StateNotifier<UserSettings> {
  final String? userId;
  final Future<void> Function()? clearPresence;
  bool _busy = false;
  late final Future<void> ready = _load();
  UserSettingsNotifier(this.userId, {this.clearPresence}) : super(const UserSettings()) {
    ready;
  }

  String _key(String setting) => 'user_settings.${userId ?? 'guest'}.$setting';
  Future<void> _load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      // Honor the old privacy choice on upgrade, then save per account.
      if (mounted) { state = UserSettings(loaded: true,
        notifications: prefs.getBool(_key('notifications')) ?? prefs.getBool('settings_notif') ?? true,
        activity: prefs.getBool(_key('activity')) ?? prefs.getBool('settings_activity_status') ?? true); }
    } catch (_) {
      // Do not publish presence when preferences could not be read.
      if (mounted) state = const UserSettings(loaded: true, activity: false);
    }
  }

  Future<void> setNotifications(bool value) => _save(notifications: value);
  Future<void> setActivity(bool value) => _save(activity: value);
  Future<void> _save({bool? notifications, bool? activity}) async {
    await ready;
    if (_busy || !mounted) return;
    _busy = true;
    final previous = state;
    final next = UserSettings(loaded: true,
      notifications: notifications ?? previous.notifications,
      activity: activity ?? previous.activity);
    SharedPreferences? prefs;
    try {
      prefs = await SharedPreferences.getInstance();
      final key = _key(activity != null ? 'activity' : 'notifications');
      if (!await prefs.setBool(key, activity ?? notifications!)) {
        throw StateError('Preference was not saved');
      }
      if (mounted) state = next;
      if (activity == false) await clearPresence?.call();
    } catch (_) {
      if (mounted) state = previous;
      try {
        await prefs?.setBool(_key(activity != null ? 'activity' : 'notifications'),
          activity != null ? previous.activity : previous.notifications);
      } catch (_) { /* Preserve the original failure even if rollback storage fails. */ }
      rethrow;
    } finally { _busy = false; }
  }
}

final userSettingsProvider = StateNotifierProvider<UserSettingsNotifier, UserSettings>((ref) {
  final userId = ref.watch(sessionUserIdProvider);
  return UserSettingsNotifier(userId, clearPresence: () async {
    if (userId == null || SupabaseService.currentUser?.id != userId) return;
    await SupabaseService.client.from('profiles').update({'last_seen_at': null}).eq('id', userId);
  });
});
