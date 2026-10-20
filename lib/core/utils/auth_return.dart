import 'dart:async';
import 'package:shared_preferences/shared_preferences.dart';

class AuthReturn {
  static String? _destination;
  static Future<void> _writes = Future<void>.value();
  static String? valid(String? value) {
    if (value == null || value.length > 500 || value.contains('\\')) {
      return null;
    }
    final uri = Uri.tryParse(value);
    if (uri == null ||
        uri.hasScheme ||
        uri.hasAuthority ||
        !value.startsWith('/') ||
        value.startsWith('//') ||
        uri.hasFragment) {
      return null;
    }
    if (!RegExp(r'^/(creator|post|place|collections)/[^/]+$')
            .hasMatch(uri.path) &&
        !RegExp(r'^/dm/[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$')
            .hasMatch(uri.path) &&
        !{'/feed', '/explore', '/discovery', '/profile', '/dm', '/privacy'}
            .contains(uri.path)) {
      return null;
    }
    if (uri.path == '/post/create') return null;
    return uri.toString();
  }

  static String get destination => _destination ?? '/feed';
  static bool get hasDestination => _destination != null;
  static Future<void> restore() async {
    try {
      await _writes;
      final prefs = await SharedPreferences.getInstance();
      _destination = valid(prefs.getString('social_auth_return'));
    } catch (_) {}
  }

  static void remember(String? value) {
    final next = valid(value);
    if (next == null || next == _destination) return;
    _destination = next;
    _persist(next);
  }

  static void clear() {
    _destination = null;
    _persist(null);
  }

  static void _persist(String? value) {
    _writes = _writes.then((_) => _save(value));
    unawaited(_writes);
  }

  static Future<void> _save(String? value) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      if (value == null) {
        await prefs.remove('social_auth_return');
      } else {
        await prefs.setString('social_auth_return', value);
      }
    } catch (_) {}
  }
}
