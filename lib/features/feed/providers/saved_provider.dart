import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/services/supabase_service.dart';
import '../../auth/providers/auth_provider.dart';

const savedPostReadError =
    'Хадгалсан төлөвийг шалгаж чадсангүй. Дахин оролдоорой.';
const savedPostRefreshError =
    'Өөрчлөлт хадгалагдсан. Жагсаалтыг дахин татаж чадсангүй.';

/// Хадгалсан постын id-ийн олонлог
final savedPostIdsProvider = FutureProvider<Set<String>>((ref) async {
  final me = ref.watch(sessionUserIdProvider);
  if (me == null) return {};
  final data = await SupabaseService.client
      .from('saved_posts')
      .select('post_id')
      .eq('user_id', me)
      .timeout(const Duration(seconds: 15));
  return (data as List).map((e) => e['post_id'] as String).toSet();
});

class SavedService {
  /// null = амжилттай, String = Монгол алдааны мессеж (snackbar-т)
  static Future<String?> toggle(String postId, bool currentlySaved) async {
    final me = SupabaseService.currentUser?.id;
    if (me == null) return 'Нэвтэрнэ үү';
    try {
      if (currentlySaved) {
        await SupabaseService.client
            .from('saved_posts')
            .delete()
            .eq('user_id', me)
            .eq('post_id', postId);
      } else {
        await SupabaseService.client
            .from('saved_posts')
            .insert({'user_id': me, 'post_id': postId});
      }
      return null;
    } catch (_) {
      return currentlySaved
          ? 'Хадгалснаа хасаж чадсангүй'
          : 'Хадгалж чадсангүй. Дахин оролдоно уу';
    }
  }
}
