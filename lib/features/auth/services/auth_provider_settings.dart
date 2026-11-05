import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../../core/constants/app_constants.dart';

class AuthProviderAvailability {
  final bool google, apple;
  const AuthProviderAvailability({required this.google, required this.apple});
  bool get anyEnabled => google || apple;
}

class AuthProviderCheckFailure implements Exception {
  final String message;
  const AuthProviderCheckFailure(this.message);
}

/// Only public provider flags are cached. No session, token, or provider secret
/// is read or sent. A fresh check still runs before Google leaves the app.
class AuthProviderSettings {
  static final shared = AuthProviderSettings();
  final http.Client? _client;
  final DateTime Function() _now;
  final Duration cacheDuration;
  AuthProviderAvailability? _cached;
  DateTime? _checkedAt;
  Future<AuthProviderAvailability>? _pending;

  AuthProviderSettings(
      {http.Client? client,
      DateTime Function()? now,
      this.cacheDuration = const Duration(minutes: 1)})
      : _client = client,
        _now = now ?? DateTime.now;

  Future<AuthProviderAvailability> fetch({bool refresh = false}) {
    if (!refresh &&
        _cached != null &&
        _checkedAt != null &&
        _now().difference(_checkedAt!) < cacheDuration) {
      return Future.value(_cached);
    }
    if (_pending != null) return _pending!;
    final request = _load();
    _pending = request;
    // Attach the cleanup to the returned future, so failures have one owner.
    return request.whenComplete(() {
      if (identical(_pending, request)) _pending = null;
    });
  }

  Future<AuthProviderAvailability> _load() async {
    final client = _client ?? http.Client();
    try {
      final response = await client.get(
        Uri.parse('${AppConstants.supabaseUrl}/auth/v1/settings'),
        headers: {'apikey': AppConstants.supabaseAnonKey},
      ).timeout(const Duration(seconds: 12));
      if (response.statusCode != 200) {
        throw const FormatException();
      }
      final data = jsonDecode(response.body);
      final external = data is Map ? data['external'] : null;
      if (external is! Map ||
          external['google'] is! bool ||
          external['apple'] is! bool) {
        throw const FormatException();
      }
      final result = AuthProviderAvailability(
          google: external['google'] as bool, apple: external['apple'] as bool);
      _cached = result;
      _checkedAt = _now();
      return result;
    } catch (_) {
      _cached = null;
      _checkedAt = null;
      throw const AuthProviderCheckFailure(
          'Apple, Google нэвтрэлтийг шалгаж чадсангүй. Дахин оролдоно уу.');
    } finally {
      if (_client == null) client.close();
    }
  }

  Future<void> requireGoogle() async {
    if (!(await fetch(refresh: true)).google) {
      throw const AuthProviderCheckFailure(
          'Google нэвтрэлт одоогоор идэвхгүй байна. Имэйлээр нэвтэрнэ үү.');
    }
  }
}
