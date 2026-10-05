import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'app_colors.dart';

/// App-wide theme mode (System / Light / Dark), persisted in SharedPreferences.
/// main.dart watches this; Settings → Appearance changes it.
final themeModeProvider = StateNotifierProvider<ThemeModeNotifier, ThemeMode>(
    (ref) => ThemeModeNotifier());

class ThemeModeNotifier extends StateNotifier<ThemeMode>
    with WidgetsBindingObserver {
  ThemeModeNotifier({
    Future<String?> Function()? readMode,
    Future<bool> Function(String)? writeMode,
  })  : _readMode = readMode ?? _readSavedMode,
        _writeMode = writeMode ?? _writeSavedMode,
        super(ThemeMode.dark) {
    _applyBrightness(ThemeMode.dark);
    // System горимд OS-ийн гэрэл/харанхуй амьдаар солигдоход дагаж мэдрэхийн тулд
    WidgetsBinding.instance.addObserver(this);
    ready = _load();
  }

  static const _key = 'theme_mode';
  final Future<String?> Function() _readMode;
  final Future<bool> Function(String) _writeMode;

  /// Completes once the previous choice has been read, even if storage fails.
  late final Future<void> ready;
  Future<void> _pendingWrite = Future<void>.value();
  ThemeMode _persistedMode = ThemeMode.dark;
  int _revision = 0;

  static Future<String?> _readSavedMode() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_key);
  }

  static Future<bool> _writeSavedMode(String value) async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.setString(_key, value);
  }

  /// OS-ийн гэрэлтэлт солигдлоо. System горимд байвал dyn* флагийг шинэчилнэ.
  /// (MaterialApp themeMode:system үедээ subtree-гээ дахин зурдаг тул getter-ууд
  /// шинэ утгыг уншина; манай global флаг хоцрохгүй байх нь чухал.)
  @override
  void didChangePlatformBrightness() {
    if (mounted && state == ThemeMode.system) {
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
      ThemeMode.dark => true,
      ThemeMode.light => false,
      ThemeMode.system =>
        WidgetsBinding.instance.platformDispatcher.platformBrightness ==
            Brightness.dark,
    };
  }

  Future<void> _load() async {
    try {
      final saved = _parse(await _readMode());
      if (!mounted) return;
      _persistedMode = saved;
      // A tap made during startup must win over the older stored choice.
      if (_revision == 0) _applyMode(saved);
    } catch (_) {
      // Keep the default, or a newer choice the person has already made.
    }
  }

  Future<void> setMode(ThemeMode mode) async {
    if (!mounted) throw StateError('Theme settings have been disposed.');
    final revision = ++_revision;
    _applyMode(mode);
    // Serialize writes so a slow older save cannot replace a newer choice.
    final operation = _pendingWrite.then((_) async {
      await ready;
      if (!mounted) return;
      try {
        final saved = await _writeMode(mode.name);
        if (!saved) throw StateError('Theme settings could not be saved.');
        if (mounted) _persistedMode = mode;
      } catch (_) {
        // SharedPreferences may change its cache before reporting a failure.
        // Restore it before the next queued write, preserving the first error.
        if (mounted) {
          try {
            await _writeMode(_persistedMode.name);
          } catch (_) {
            // A storage outage may prevent restoration as well.
          }
        }
        rethrow;
      }
    });
    _pendingWrite = operation.catchError((Object _) {});
    try {
      await operation;
    } catch (_) {
      if (mounted && revision == _revision) _applyMode(_persistedMode);
      rethrow;
    }
  }

  void _applyMode(ThemeMode mode) {
    _applyBrightness(mode);
    state = mode;
    _rebuildAll();
  }

  static ThemeMode _parse(String? v) => switch (v) {
        'light' => ThemeMode.light,
        'system' => ThemeMode.system,
        _ => ThemeMode.dark,
      };

  /// Өнгөний токенууд (AppColors.bg*, text* …) нь `isDarkMode` глобал
  /// флагаас уншдаг static getter. Theme-ээс хамааралгүй widget-ууд
  /// горим солигдоход өөрөө rebuild хийгдэхгүй тул дараагийн фрэймд
  /// БҮХ элементийг дахин build хийлгэнэ. State (scroll, input, навигаци)
  /// хадгалагдана — зөвхөн дахин зурна.
  void _rebuildAll() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
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
