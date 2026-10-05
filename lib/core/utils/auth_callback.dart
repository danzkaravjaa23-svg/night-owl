/// Preserve web deployment paths while stripping OAuth codes/tokens from the
/// return URL. Native callbacks match the platform URL scheme registration.
String oauthRedirectUrl({required bool isWeb, required Uri baseUri}) {
  if (!isWeb) return 'com.nightowl.ub://login-callback/';
  return Uri(
          scheme: baseUri.scheme,
          host: baseUri.host,
          port: baseUri.hasPort ? baseUri.port : null,
          path: baseUri.path.isEmpty ? '/' : baseUri.path)
      .toString();
}

bool hasOAuthCallback(Uri uri) =>
    uri.queryParameters.containsKey('code') ||
    uri.queryParameters.containsKey('error') ||
    uri.fragment.contains('access_token=') ||
    uri.fragment.contains('error_description=');

/// Browser history should not retain consumed login credentials after reload.
Uri cleanAuthCallbackUrl(Uri uri) {
  const authKeys = {
    'code',
    'state',
    'error',
    'error_code',
    'error_description',
    'access_token',
    'refresh_token',
    'provider_token',
    'provider_refresh_token',
    'expires_in',
    'expires_at',
    'token_type',
    'token_hash',
    'type'
  };
  final keep = Map<String, List<String>>.from(uri.queryParametersAll)
    ..removeWhere((key, _) => authKeys.contains(key));
  return Uri(
      scheme: uri.scheme,
      host: uri.host,
      port: uri.hasPort ? uri.port : null,
      path: uri.path,
      queryParameters: keep.isEmpty ? null : keep,
      fragment: '/auth');
}

String oauthCallbackErrorMessage(String? code) => switch (code) {
      'access_denied' =>
        'Нэвтрэлт цуцлагдлаа. Дахин оролдох эсвэл өөр аргаар нэвтэрнэ үү.',
      'provider_disabled' =>
        'Энэ нэвтрэх арга одоогоор идэвхгүй байна. Өөр аргаар нэвтэрнэ үү.',
      _ =>
        'Нэвтрэх холбоос хүчингүй эсвэл хугацаа нь дууссан байна. Дахин нэвтэрнэ үү.',
    };
