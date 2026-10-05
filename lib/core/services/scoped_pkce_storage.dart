import 'package:supabase_flutter/supabase_flutter.dart';

/// Pending OAuth verifiers belong to one independent backend origin.
class ScopedPkceStorage extends GotrueAsyncStorage {
  ScopedPkceStorage(this.namespace, this.delegate);

  final String namespace;
  final GotrueAsyncStorage delegate;

  String _key(String key) => '$namespace:$key';

  @override
  Future<String?> getItem({required String key}) =>
      delegate.getItem(key: _key(key));

  @override
  Future<void> setItem({required String key, required String value}) =>
      delegate.setItem(key: _key(key), value: value);

  @override
  Future<void> removeItem({required String key}) =>
      delegate.removeItem(key: _key(key));
}
