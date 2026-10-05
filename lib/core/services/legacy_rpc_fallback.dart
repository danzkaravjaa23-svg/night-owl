import 'package:supabase_flutter/supabase_flutter.dart';
import '../constants/app_constants.dart';

/// Only the existing managed backend may use the older direct-table path.
/// PGRST202 identifies an unresolved RPC; SQL, auth and transport errors do not.
bool canUseLegacyRpcFallback(
  Object error, {
  required String rpcName,
  String backendMode = AppConstants.backendMode,
  String backendUrl = AppConstants.backendUrl,
}) {
  final origin = Uri.tryParse(backendUrl);
  if (backendMode != 'supabase' ||
      origin == null ||
      origin.scheme != 'https' ||
      origin.userInfo.isNotEmpty ||
      !(origin.host.endsWith('.supabase.co') ||
          origin.host.endsWith('.supabase.in')) ||
      error is! PostgrestException ||
      error.code != 'PGRST202') {
    return false;
  }

  // Match the requested public function, not another missing function or an
  // unrelated 404. PostgREST versions use these two schema-cache wordings.
  final function = RegExp.escape('public.$rpcName');
  return RegExp(
              '^Could not find the function $function(?:\\([^)]*\\)| without parameters) in the schema cache\$')
          .hasMatch(error.message) ||
      RegExp('^Could not find the $function\\([^)]*\\) function in the schema cache\$')
          .hasMatch(error.message);
}
