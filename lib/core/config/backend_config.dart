import 'dart:convert';

enum BackendMode { supabase, postgres }

/// The PostgreSQL mode targets an HTTPS gateway, never a database connection.
/// Auth, Storage and Realtime must share this gateway before cutting over.
class BackendConfig {
  const BackendConfig._(this.mode, this.url, this.publicKey);

  final BackendMode mode;
  final Uri url;
  final String publicKey;

  /// Keep current sessions during preparation. Independent gateways get an
  /// origin-specific key so credentials cannot cross staging/production hosts.
  String get sessionStorageKey => mode == BackendMode.supabase
      ? 'sb-${url.host.split('.').first}-auth-token'
      : 'nightowl-postgres-${base64Url.encode(utf8.encode(url.toString())).replaceAll('=', '')}-auth-token';

  static BackendConfig parse({
    required String mode,
    required String url,
    required String publicKey,
    required bool allowLocalHttp,
  }) {
    final selected = switch (mode) {
      'supabase' => BackendMode.supabase,
      'postgres' => BackendMode.postgres,
      _ => throw const FormatException('Unknown backend mode.'),
    };
    final origin = Uri.tryParse(url.trim());
    if (origin == null ||
        origin.host.isEmpty ||
        origin.userInfo.isNotEmpty ||
        origin.hasQuery ||
        origin.hasFragment ||
        (origin.path.isNotEmpty && origin.path != '/')) {
      throw const FormatException('Backend URL must be an API origin.');
    }
    final local = {'localhost', '127.0.0.1', '::1'}.contains(origin.host);
    if (origin.scheme != 'https' &&
        !(allowLocalHttp && local && origin.scheme == 'http')) {
      throw const FormatException('Backend URL requires HTTPS.');
    }
    if (selected == BackendMode.postgres &&
        (origin.host == 'supabase.co' ||
            origin.host.endsWith('.supabase.co') ||
            origin.host == 'supabase.in' ||
            origin.host.endsWith('.supabase.in'))) {
      throw const FormatException(
          'PostgreSQL mode requires an independent API.');
    }
    final key = publicKey.trim();
    if (key.isEmpty || key.startsWith('sb_secret_')) {
      throw const FormatException('A public backend key is required.');
    }
    final parts = key.split('.');
    if (parts.length == 3) {
      Map<String, dynamic> claims;
      try {
        claims = jsonDecode(
                utf8.decode(base64Url.decode(base64Url.normalize(parts[1]))))
            as Map<String, dynamic>;
      } catch (_) {
        throw const FormatException('Invalid public backend key.');
      }
      if (claims['role'] != 'anon') {
        throw const FormatException(
            'Only an anonymous JWT belongs in the app.');
      }
      if (claims['sub'] != null && claims['sub'] != '') {
        throw const FormatException('A user credential cannot be public.');
      }
      if (selected == BackendMode.postgres) {
        final audience = claims['aud'];
        if (audience != 'authenticated' &&
            !(audience is List && audience.contains('authenticated'))) {
          throw const FormatException(
              'Public JWT audience must match the API.');
        }
      }
    } else if (selected == BackendMode.postgres ||
        !key.startsWith('sb_publishable_') ||
        key.length <= 'sb_publishable_'.length) {
      throw const FormatException('Use an anonymous JWT or a publishable key.');
    }
    return BackendConfig._(selected, origin.replace(path: ''), key);
  }
}
