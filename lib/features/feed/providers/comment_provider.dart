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
        final me = SupabaseService.currentUser?.id;

        // Аль сэтгэгдлийг би лайк хийсэн бэ?
        final Set<String> likedIds = {};
        if (me != null) {
          try {
            final likes = await SupabaseService.client
                .from('comment_likes')
                .select('comment_id')
                .eq('user_id', me)
                .inFilter('comment_id', comments.map((c) => c.id).toList());
            for (final l in (likes as List)) {
              final id = l['comment_id'];
              if (id != null) likedIds.add(id.toString());
            }
          } catch (_) {}
        }

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
            return Comment.fromJson({
              'id': c.id,
              'post_id': c.postId,
              'user_id': c.userId,
              'body': c.body,
              'parent_id': c.parentId,
              'likes_count': c.likesCount,
              'is_liked_by_me': likedIds.contains(c.id),
              'created_at': c.createdAt.toIso8601String(),
              if (p != null) 'profiles': p,
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
    String? parentId,
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
        if (parentId != null) 'parent_id': parentId,
      });
      return null;
    } catch (e) {
      return e.toString();
    }
  }

  /// Сэтгэгдэл лайк toggle
  static Future<String?> toggleLike(String commentId, bool currentlyLiked) async {
    final user = SupabaseService.currentUser;
    if (user == null) return 'Нэвтэрнэ үү';
    try {
      if (currentlyLiked) {
        await SupabaseService.client.from('comment_likes').delete().match({
          'comment_id': commentId, 'user_id': user.id,
        });
      } else {
        await SupabaseService.client.from('comment_likes').upsert({
          'comment_id': commentId, 'user_id': user.id,
        }, onConflict: 'comment_id, user_id');
      }
      return null;
    } catch (e) {
      return e.toString();
    }
  }

  /// null = амжилттай, String = алдааны мессеж (snackbar-т)
  static Future<String?> deleteComment(String commentId) async {
    final user = SupabaseService.currentUser;
    if (user == null) return 'Нэвтэрнэ үү';
    try {
      await SupabaseService.client
          .from('comments')
          .delete()
          .eq('id', commentId)
          .eq('user_id', user.id);
      return null;
    } catch (_) {
      return 'Сэтгэгдэл устгаж чадсангүй';
    }
  }
}
