import 'package:flutter/foundation.dart';
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
  Future<void>? _inflight;

  /// Дараагийн хуудас бий эсэх — footer spinner-ийг зөв харуулна
  final ValueNotifier<bool> hasMore = ValueNotifier(true);
  /// Хуудас ачаалахад алдаа гарсан эсэх — footer дээр retry харуулна
  final ValueNotifier<bool> pageError = ValueNotifier(false);

  @override
  void dispose() {
    hasMore.dispose();
    pageError.dispose();
    super.dispose();
  }

  Future<void> loadFeed({bool refresh = false}) async {
    // In-flight ачаалалтай үед: pagination бол алгасна,
    // refresh бол дуусахыг нь хүлээгээд дараа нь шинэчилнэ (silent no-op болохгүй)
    while (_loading) {
      if (!refresh) return;
      try { await _inflight; } catch (_) {}
    }
    if (!refresh && !_hasMore) return;
    final f = _doLoad(refresh: refresh);
    _inflight = f;
    await f;
  }

  Future<void> _doLoad({required bool refresh}) async {
    if (refresh) {
      _cursor  = null;
      _hasMore = true;
      // Хуучин дата байвал skeleton flash хийхгүй — RefreshIndicator л хангалттай
      if (state.value == null) state = const AsyncValue.loading();
    }
    _loading = true;
    if (pageError.value) pageError.value = false;

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
      hasMore.value = _hasMore;
    } catch (e, st) {
      if (refresh && state.value == null) {
        // Анхны ачаалал бүтэлгүйтвэл бүтэн error state
        state = AsyncValue.error(e, st);
      } else {
        // Дата хэвээр үлдээж, footer дээр retry товч харуулна
        pageError.value = true;
      }
    } finally {
      _loading = false;
    }
  }

  // ── Optimistic like toggle (фийдэд байгаа пост) ─────────────────────────────
  /// true = амжилттай, false = DB бичилт бүтэлгүйтэж rollback хийсэн
  Future<bool> toggleLike(String postId) async {
    final user = SupabaseService.currentUser;
    if (user == null) return false;

    final current = List<Post>.from(state.value ?? []);
    final idx = current.indexWhere((p) => p.id == postId);
    if (idx == -1) return false;

    final post     = current[idx];
    final nowLiked = !post.isLikedByMe;

    // Optimistic update
    current[idx] = post.copyWith(
      isLikedByMe: nowLiked,
      likesCount:  post.likesCount + (nowLiked ? 1 : -1),
    );
    state = AsyncValue.data(current);

    try {
      await _writeLike(user.id, postId, nowLiked);
      return true;
    } catch (_) {
      // Rollback
      final rollback = List<Post>.from(state.value ?? []);
      final i = rollback.indexWhere((p) => p.id == postId);
      if (i != -1) rollback[i] = post;
      state = AsyncValue.data(rollback);
      return false;
    }
  }

  // ── Like toggle by id — фийдэд байхгүй пост дээр ч DB бичилт хийнэ ─────────
  /// Post detail гэх мэт фийдийн гаднаас нээгдсэн постод хэрэглэнэ.
  /// true = амжилттай (caller optimistic state-ээ хадгална), false = rollback хий.
  Future<bool> toggleLikeById(String postId, bool currentlyLiked) async {
    final user = SupabaseService.currentUser;
    if (user == null) return false;

    // Фийдэд байвал optimistic toggle (feed картууд ч мөн шинэчлэгдэнэ)
    if ((state.value ?? []).any((p) => p.id == postId)) {
      return toggleLike(postId);
    }
    // Фийдэд байхгүй — DB рүү шууд бичнэ
    try {
      await _writeLike(user.id, postId, !currentlyLiked);
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<void> _writeLike(String userId, String postId, bool like) async {
    if (like) {
      await SupabaseService.client.from('likes').insert({
        'user_id': userId,
        'post_id': postId,
      });
    } else {
      await SupabaseService.client
          .from('likes')
          .delete()
          .eq('user_id', userId)
          .eq('post_id', postId);
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
