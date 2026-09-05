import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/services/supabase_service.dart';

/// Хадгалсан постын id-ийн олонлог
final savedPostIdsProvider = FutureProvider<Set<String>>((ref) async {
  final me = SupabaseService.currentUser?.id;
  if (me == null) return {};
  try {
    final data = await SupabaseService.client
        .from('saved_posts').select('post_id').eq('user_id', me);
    return (data as List).map((e) => e['post_id'] as String).toSet();
  } catch (_) {
    return {};
  }
});

class SavedService {
  /// null = амжилттай, String = Монгол алдааны мессеж (snackbar-т)
  static Future<String?> toggle(String postId, bool currentlySaved) async {
    final me = SupabaseService.currentUser?.id;
    if (me == null) return 'Нэвтэрнэ үү';
    try {
      if (currentlySaved) {
        await SupabaseService.client.from('saved_posts')
            .delete().eq('user_id', me).eq('post_id', postId);
      } else {
        await SupabaseService.client.from('saved_posts')
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
