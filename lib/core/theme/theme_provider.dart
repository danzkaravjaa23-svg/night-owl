import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// App-wide theme mode (System / Light / Dark), persisted in SharedPreferences.
/// main.dart watches this; Settings → Appearance changes it.
final themeModeProvider =
    StateNotifierProvider<ThemeModeNotifier, ThemeMode>(
        (ref) => ThemeModeNotifier());

class ThemeModeNotifier extends StateNotifier<ThemeMode> {
  ThemeModeNotifier() : super(ThemeMode.dark) {
    _load();
  }

  static const _key = 'theme_mode';

  Future<void> _load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      state = _parse(prefs.getString(_key));
    } catch (_) {/* default dark */}
  }

  Future<void> setMode(ThemeMode mode) async {
    state = mode;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_key, mode.name);
    } catch (_) {}
  }

  static ThemeMode _parse(String? v) => switch (v) {
        'light'  => ThemeMode.light,
        'system' => ThemeMode.system,
        _        => ThemeMode.dark,
      };
}
