import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';

import 'account_user_updater.dart';

class AccountMetadataFailure implements Exception {
  final String code;
  const AccountMetadataFailure(this.code);

  String get message => code == 'authentication_required'
      ? 'Нэвтрэх эрх дууссан байна. Дахин нэвтэрнэ үү.'
      : 'Бүртгэлийн мэдээллийг хадгалж чадсангүй. Дахин оролдоно уу.';

  @override
  String toString() => message;
}

/// Owner-scoped metadata changes share the guarded Auth update transport.
class AccountMetadataService {
  final AccountUserUpdater _updater;

  AccountMetadataService({
    SupabaseClient? client,
    http.Client? httpClient,
    Duration requestTimeout = const Duration(seconds: 15),
  }) : _updater = AccountUserUpdater(
          client: client,
          httpClient: httpClient,
          requestTimeout: requestTimeout,
        );

  Future<bool> update(Map<String, dynamic> data,
      {required String ownerId}) async {
    try {
      return await _updater.update({'data': data}, ownerId: ownerId);
    } on AccountUserUpdateFailure catch (error) {
      throw AccountMetadataFailure(error.code);
    }
  }
}
