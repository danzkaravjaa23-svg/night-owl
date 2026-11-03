import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';

import 'account_user_updater.dart';

class AccountCredentialsFailure implements Exception {
  final String code;
  const AccountCredentialsFailure(this.code);

  String get message => switch (code) {
        'authentication_required' =>
          'Нэвтрэх эрх дууссан байна. Дахин нэвтэрнэ үү.',
        'same_password' => 'Шинэ нууц үг хуучин нууц үгээс өөр байх ёстой.',
        'weak_password' =>
          'Нууц үг серверийн аюулгүй байдлын шаардлага хангахгүй байна. Илүү урт, таахад хэцүү нууц үг сонгоно уу.',
        'reauthentication_needed' ||
        'reauthentication_not_valid' =>
          'Аюулгүй байдлын баталгаажуулалт хэрэгтэй. Дахин нэвтэрч оролдоно уу.',
        _ =>
          'Нууц үг шинэчилснийг баталж чадсангүй. Сүлжээгээ шалгаж, шаардлагатай бол шинэ нууц үгээрээ нэвтрэхийг шалгана уу.',
      };

  @override
  String toString() => message;
}

/// Never lets a late password response replace another account's session.
class AccountCredentialsService {
  final AccountUserUpdater _updater;

  AccountCredentialsService({
    SupabaseClient? client,
    http.Client? httpClient,
    Duration requestTimeout = const Duration(seconds: 15),
  }) : _updater = AccountUserUpdater(
          client: client,
          httpClient: httpClient,
          requestTimeout: requestTimeout,
        );

  Future<bool> updatePassword(String password,
      {required String ownerId}) async {
    try {
      return await _updater.update({'password': password}, ownerId: ownerId);
    } on AccountUserUpdateFailure catch (error) {
      throw AccountCredentialsFailure(error.code);
    }
  }
}
