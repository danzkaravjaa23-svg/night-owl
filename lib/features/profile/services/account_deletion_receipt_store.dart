import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Stores only opaque status capabilities, owner IDs, and start timestamps.
/// Apple authorization codes and identity tokens are never persisted.
class AccountDeletionReceiptStore {
  static const _key = 'nightowl.account-erasure.receipts.v1';
  final FlutterSecureStorage _storage;
  const AccountDeletionReceiptStore(
      {FlutterSecureStorage storage = const FlutterSecureStorage()})
      : _storage = storage;
  Future<String?> read() => _storage.read(key: _key);
  Future<void> write(String value) => _storage.write(key: _key, value: value);
}
