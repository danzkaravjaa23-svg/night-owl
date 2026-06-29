import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/services/supabase_service.dart';
import '../../../core/constants/app_constants.dart';
import '../../../models/post.dart';

// ─── Feed posts (paginated, RPC-based for correct isLikedByMe) ───────────────
class FeedNotifier extends StateNotifier<AsyncValue<List<Post>>> {
  FeedNotifier() : super(const AsyncValue.loading()) {
    loadFeed();
  }

  DateTime? _cursor;   // сүүлд татсан постын created_at (keyset pagination)
  bool _hasMore = true;
  bool _loading = false;

  Future<void> loadFeed({bool refresh = false}) async {
    // refresh ч in-flight ачааллыг дайрахгүй (cursor/state race-ээс сэргийлнэ)
    if (_loading) return;
    if (refresh) {
      _cursor  = null;
      _hasMore = true;
      state    = const AsyncValue.loading();
    }
    if (!_hasMore) return;
    _loading = true;

    try {
      final userId = SupabaseService.currentUser?.id;
      List<Map<String, dynamic>> rows;

      if (userId != null) {
        // RPC: cursor (keyset) — offset scan байхгүй, давхардахгүй
        final data = await SupabaseService.client.rpc(
          'get_feed_cursor',
          params: {
            'p_user_id': userId,
            'p_limit':   AppConstants.feedPageSize,
            'p_before':  _cursor?.toIso8601String(),
          },
        );
        rows = (data as List).cast<Map<String, dynamic>>();
      } else {
        // Fallback: plain query with cursor
        var q = SupabaseService.client
            .from('posts')
            .select('*, profiles!user_id (id, username, avatar_url, is_verified)');
        if (_cursor != null) {
          q = q.lt('created_at', _cursor!.toIso8601String());
        }
        final data = await q
            .order('created_at', ascending: false)
            .limit(AppConstants.feedPageSize);
        rows = (data as List).cast<Map<String, dynamic>>();
      }

      final fetched = rows.map((j) => Post.fromJson(j)).toList();
      _hasMore = fetched.length == AppConstants.feedPageSize;
      if (fetched.isNotEmpty) _cursor = fetched.last.createdAt;

      // Давхардлаас сэргийлэх (cursor хилийн ижил timestamp edge case)
      final existing = refresh ? <Post>[] : (state.value ?? []);
      final seen = existing.map((p) => p.id).toSet();
      final merged = [...existing, ...fetched.where((p) => seen.add(p.id))];

      state = AsyncValue.data(merged);
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

  // ── Edit own post caption ───────────────────────────────────────────────────
  Future<void> editCaption(String postId, String caption) async {
    final user = SupabaseService.currentUser;
    if (user == null) return;
    final trimmed = caption.trim();
    try {
      await SupabaseService.client
          .from('posts')
          .update({'caption': trimmed})
          .eq('id', postId)
          .eq('user_id', user.id);
    } catch (_) { return; }
    final list = (state.value ?? []).map((p) =>
        p.id == postId ? p.copyWith(caption: trimmed) : p).toList();
    state = AsyncValue.data(list);
  }

  // ── Delete own post ─────────────────────────────────────────────────────────
  Future<bool> deletePost(String postId) async {
    final user = SupabaseService.currentUser;
    if (user == null) return false;
    try {
      await SupabaseService.client
          .from('posts')
          .delete()
          .eq('id', postId)
          .eq('user_id', user.id);
    } catch (_) {
      return false; // устгаж чадсангүй
    }
    final updated = (state.value ?? []).where((p) => p.id != postId).toList();
    state = AsyncValue.data(updated);
    return true;
  }
}

final feedProvider =
    StateNotifierProvider<FeedNotifier, AsyncValue<List<Post>>>(
        (_) => FeedNotifier());
