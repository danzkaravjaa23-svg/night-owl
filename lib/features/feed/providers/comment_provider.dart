import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/services/supabase_service.dart';
import '../../../models/comment.dart';

// ─── Comments for a post (realtime stream) ───────────────────────────────────
final commentsProvider =
    StreamProvider.family<List<Comment>, String>((ref, postId) {
  return SupabaseService.client
      .from('comments')
      .stream(primaryKey: ['id'])
      .eq('post_id', postId)
      .order('created_at', ascending: true)
      .asyncMap((rows) async {
        final comments = rows
            .cast<Map<String, dynamic>>()
            .map((r) => Comment.fromJson(r))
            .toList();

        // Enrich with author profiles in one batch query
        if (comments.isEmpty) return comments;
        final userIds = comments.map((c) => c.userId).toSet().toList();
        try {
          final profiles = await SupabaseService.client
              .from('profiles')
              .select('id, username, avatar_url')
              .inFilter('id', userIds);

          final profileMap = {
            for (final p in (profiles as List).cast<Map<String, dynamic>>())
              p['id'] as String: p
          };

          return comments.map((c) {
            final p = profileMap[c.userId];
            if (p == null) return c;
            return Comment.fromJson({
              ...{
                'id': c.id,
                'post_id': c.postId,
                'user_id': c.userId,
                'body': c.body,
                'likes_count': c.likesCount,
                'created_at': c.createdAt.toIso8601String(),
              },
              'profiles': p,
            });
          }).toList();
        } catch (_) {
          return comments;
        }
      });
});

// ─── Comment count for a post ─────────────────────────────────────────────────
final commentCountProvider = Provider.family<int, String>((ref, postId) {
  final comments = ref.watch(commentsProvider(postId));
  return comments.value?.length ?? 0;
});

// ─── Comment actions ─────────────────────────────────────────────────────────
class CommentService {
  static Future<String?> addComment({
    required String postId,
    required String body,
  }) async {
    final user = SupabaseService.currentUser;
    if (user == null) return 'Нэвтэрнэ үү';
    final trimmed = body.trim();
    if (trimmed.isEmpty) return 'Сэтгэгдэл хоосон байна';
    if (trimmed.length > 500) return 'Хэт урт (500 тэмдэгт хүртэл)';

    try {
      await SupabaseService.client.from('comments').insert({
        'post_id': postId,
        'user_id': user.id,
        'body':    trimmed,
      });
      return null;
    } catch (e) {
      return e.toString();
    }
  }

  static Future<void> deleteComment(String commentId) async {
    final user = SupabaseService.currentUser;
    if (user == null) return;
    await SupabaseService.client
        .from('comments')
        .delete()
        .eq('id', commentId)
        .eq('user_id', user.id);
  }
}
