import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/services/supabase_service.dart';
import '../../../core/constants/app_constants.dart';
import '../../../models/post.dart';

// ─── Feed posts (paginated, RPC-based for correct isLikedByMe) ───────────────
class FeedNotifier extends StateNotifier<AsyncValue<List<Post>>> {
  FeedNotifier() : super(const AsyncValue.loading()) {
    loadFeed();
  }

  int  _page    = 0;
  bool _hasMore = true;
  bool _loading = false;

  Future<void> loadFeed({bool refresh = false}) async {
    if (_loading && !refresh) return;
    if (refresh) {
      _page    = 0;
      _hasMore = true;
      state    = const AsyncValue.loading();
    }
    if (!_hasMore) return;
    _loading = true;

    try {
      final userId = SupabaseService.currentUser?.id;
      final offset = _page * AppConstants.feedPageSize;

      List<Map<String, dynamic>> rows;

      if (userId != null) {
        // RPC: correct isLikedByMe + commentsCount
        final data = await SupabaseService.client.rpc(
          'get_feed_posts',
          params: {
            'p_user_id': userId,
            'p_limit':   AppConstants.feedPageSize,
            'p_offset':  offset,
          },
        );
        rows = (data as List).cast<Map<String, dynamic>>();
      } else {
        // Fallback: plain query
        final data = await SupabaseService.client
            .from('posts')
            .select('*, profiles!user_id (id, username, avatar_url, is_verified)')
            .order('created_at', ascending: false)
            .range(offset, offset + AppConstants.feedPageSize - 1);
        rows = (data as List).cast<Map<String, dynamic>>();
      }

      final posts = rows.map((j) => Post.fromJson(j)).toList();
      _hasMore = posts.length == AppConstants.feedPageSize;
      _page++;

      state = AsyncValue.data(
        refresh ? posts : [...(state.value ?? []), ...posts],
      );
    } catch (e, st) {
      if (refresh) state = AsyncValue.error(e, st);
    } finally {
      _loading = false;
    }
  }

  // ── Optimistic like toggle ──────────────────────────────────────────────────
  Future<void> toggleLike(String postId) async {
    final user = SupabaseService.currentUser;
    if (user == null) return;

    final current = List<Post>.from(state.value ?? []);
    final idx = current.indexWhere((p) => p.id == postId);
    if (idx == -1) return;

    final post     = current[idx];
    final nowLiked = !post.isLikedByMe;

    // Optimistic update
    current[idx] = post.copyWith(
      isLikedByMe: nowLiked,
      likesCount:  post.likesCount + (nowLiked ? 1 : -1),
    );
    state = AsyncValue.data(current);

    try {
      if (nowLiked) {
        await SupabaseService.client.from('likes').insert({
          'user_id': user.id,
          'post_id': postId,
        });
      } else {
        await SupabaseService.client
            .from('likes')
            .delete()
            .eq('user_id', user.id)
            .eq('post_id', postId);
      }
    } catch (_) {
      // Rollback
      final rollback = List<Post>.from(state.value ?? []);
      final i = rollback.indexWhere((p) => p.id == postId);
      if (i != -1) rollback[i] = post;
      state = AsyncValue.data(rollback);
    }
  }

  // ── Create post ─────────────────────────────────────────────────────────────
  Future<String?> createPost({
    required String caption,
    required String mediaUrl,
    String mediaType = 'image',
    String? venueId,
  }) async {
    final user = SupabaseService.currentUser;
    if (user == null) return 'Not logged in';

    try {
      await SupabaseService.client.from('posts').insert({
        'user_id':    user.id,
        'venue_id':   venueId,
        'caption':    caption,
        'media_url':  mediaUrl,
        'media_type': mediaType,
      });
      await loadFeed(refresh: true);
      return null;
    } catch (e) {
      return e.toString();
    }
  }

  // ── Delete own post ─────────────────────────────────────────────────────────
  Future<void> deletePost(String postId) async {
    final user = SupabaseService.currentUser;
    if (user == null) return;
    await SupabaseService.client
        .from('posts')
        .delete()
        .eq('id', postId)
        .eq('user_id', user.id);
    final updated = (state.value ?? []).where((p) => p.id != postId).toList();
    state = AsyncValue.data(updated);
  }
}

final feedProvider =
    StateNotifierProvider<FeedNotifier, AsyncValue<List<Post>>>(
        (_) => FeedNotifier());
