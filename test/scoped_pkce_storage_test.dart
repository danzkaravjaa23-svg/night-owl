import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:night_owl_ub/core/services/scoped_pkce_storage.dart';

class MemoryStorage extends GotrueAsyncStorage {
  final values = <String, String>{};
  @override
  Future<String?> getItem({required String key}) async => values[key];
  @override
  Future<void> setItem({required String key, required String value}) async {
    values[key] = value;
  }

  @override
  Future<void> removeItem({required String key}) async {
    values.remove(key);
  }
}

void main() {
  test('parallel OAuth flows cannot overwrite or consume another origin',
      () async {
    final shared = MemoryStorage();
    final production = ScopedPkceStorage('production-origin', shared);
    final staging = ScopedPkceStorage('staging-origin', shared);
    const key = 'supabase.auth.token-code-verifier';
    await Future.wait([
      production.setItem(key: key, value: 'production-verifier'),
      staging.setItem(key: key, value: 'staging-verifier'),
    ]);
    expect(await production.getItem(key: key), 'production-verifier');
    expect(await staging.getItem(key: key), 'staging-verifier');
    await staging.removeItem(key: key);
    expect(await staging.getItem(key: key), isNull);
    expect(await production.getItem(key: key), 'production-verifier');
    expect(await shared.getItem(key: key), isNull);
  });
}
