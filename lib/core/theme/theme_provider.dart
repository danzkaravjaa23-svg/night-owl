import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'app_colors.dart';

/// App-wide theme mode (System / Light / Dark), persisted in SharedPreferences.
/// main.dart watches this; Settings → Appearance changes it.
final themeModeProvider =
    StateNotifierProvider<ThemeModeNotifier, ThemeMode>(
        (ref) => ThemeModeNotifier());

class ThemeModeNotifier extends StateNotifier<ThemeMode>
    with WidgetsBindingObserver {
  ThemeModeNotifier() : super(ThemeMode.dark) {
    _applyBrightness(ThemeMode.dark);
    // System горимд OS-ийн гэрэл/харанхуй амьдаар солигдоход дагаж мэдрэхийн тулд
    WidgetsBinding.instance.addObserver(this);
    _load();
  }

  static const _key = 'theme_mode';

  /// OS-ийн гэрэлтэлт солигдлоо. System горимд байвал dyn* флагийг шинэчилнэ.
  /// (MaterialApp themeMode:system үедээ subtree-гээ дахин зурдаг тул getter-ууд
  /// шинэ утгыг уншина; манай global флаг хоцрохгүй байх нь чухал.)
  @override
  void didChangePlatformBrightness() {
    if (state == ThemeMode.system) _applyBrightness(state);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  /// AppColors-ийн динамик (dyn*) getter-уудад идэвхтэй горимыг мэдэгдэнэ.
  /// State солигдоход MaterialApp бүх мод-оо rebuild хийдэг тул
  /// getter-ууд build бүрт зөв утга буцаана.
  static void _applyBrightness(ThemeMode mode) {
    AppColors.isDarkMode = switch (mode) {
      ThemeMode.dark  => true,
      ThemeMode.light => false,
      ThemeMode.system => WidgetsBinding
              .instance.platformDispatcher.platformBrightness ==
          Brightness.dark,
    };
  }

  Future<void> _load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      state = _parse(prefs.getString(_key));
      _applyBrightness(state);
    } catch (_) {/* default dark */}
  }

  Future<void> setMode(ThemeMode mode) async {
    _applyBrightness(mode);
    state = mode;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_key, mode.name);
    } catch (_) {}
  }

  // Гэрэл горим түр хаалттай: features дотор AppColors.dyn* getter-ууд хараахан
  // ашиглагдаагүй (≈950 газар харанхуй өнгө хатуу бичигдсэн) тул light горимд
  // хагас эвдэрсэн дэлгэц гарна. Тохиргооны унтраалгыг нь авсан; энд хадгалагдсан
  // хуучин сонголтыг ч мөн харанхуй руу татна — эс бөгөөс өмнө нь асаасан
  // хэрэглэгч гарц олдохгүй гацна. dyn* нүүлгэлт дуусахад буцааж нээнэ.
  static ThemeMode _parse(String? v) => switch (v) {
        'light'  => ThemeMode.dark, // TODO(dyn-colors): => ThemeMode.light
        'system' => ThemeMode.system,
        _        => ThemeMode.dark,
      };
}
