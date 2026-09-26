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
    if (state == ThemeMode.system) {
      _applyBrightness(state);
      _rebuildAll();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  /// AppColors-ийн динамик (dyn*) getter-уудад идэвхтэй горимыг мэдэгдэнэ.
  /// Флаг солигдсоны дараа [_rebuildAll] бүх элементийг дахин зурна.
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
      final saved = _parse(prefs.getString(_key));
      _applyBrightness(saved);
      state = saved;
      _rebuildAll();
    } catch (_) {/* default dark */}
  }

  Future<void> setMode(ThemeMode mode) async {
    _applyBrightness(mode);
    state = mode;
    _rebuildAll();
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

  /// Өнгөний токенууд (AppColors.bg*, text* …) нь `isDarkMode` глобал
  /// флагаас уншдаг static getter. Theme-ээс хамааралгүй widget-ууд
  /// горим солигдоход өөрөө rebuild хийгдэхгүй тул дараагийн фрэймд
  /// БҮХ элементийг дахин build хийлгэнэ. State (scroll, input, навигаци)
  /// хадгалагдана — зөвхөн дахин зурна.
  static void _rebuildAll() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final root = WidgetsBinding.instance.rootElement;
      if (root == null) return;
      void visit(Element e) {
        e.markNeedsBuild();
        e.visitChildren(visit);
      }
      root.visitChildren(visit);
    });
    WidgetsBinding.instance.ensureVisualUpdate();
  }
}
