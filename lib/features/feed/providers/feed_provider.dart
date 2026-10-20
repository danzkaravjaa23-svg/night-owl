import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/services/supabase_service.dart';
import '../../../core/constants/app_constants.dart';
import '../../auth/providers/auth_provider.dart';
import '../../../models/post.dart';
import '../../discovery/services/discovery_service.dart';

// ─── Feed posts (paginated, RPC-based for correct isLikedByMe) ───────────────
class FeedNotifier extends StateNotifier<AsyncValue<List<Post>>> {
  final bool followingOnly;
  FeedNotifier({this.followingOnly=false}) : super(const AsyncValue.loading()) {
    loadFeed();
  }

  DateTime? _cursor; // сүүлд татсан постын created_at (keyset pagination)
  String? _cursorId;
  bool _hasMore = true;
  bool _loading = false;
  Future<void>? _inflight;
  final _liking = <String>{};

  /// Дараагийн хуудас бий эсэх — footer spinner-ийг зөв харуулна
  final ValueNotifier<bool> hasMore = ValueNotifier(true);

  /// Хуудас ачаалахад алдаа гарсан эсэх — footer дээр retry харуулна
  final ValueNotifier<bool> pageError = ValueNotifier(false);

  /// Real request state, separate from whether another page may exist.
  final ValueNotifier<bool> isFetching = ValueNotifier(false);

  @override
  void dispose() {
    hasMore.dispose();
    pageError.dispose();
    isFetching.dispose();
    super.dispose();
  }

  Future<void> loadFeed({bool refresh = false}) async {
    if (!mounted) return;
    // In-flight ачаалалтай үед: pagination бол алгасна,
    // refresh бол дуусахыг нь хүлээгээд дараа нь шинэчилнэ (silent no-op болохгүй)
    while (_loading) {
      if (!refresh) return;
      try {
        await _inflight;
      } catch (_) {}
      if (!mounted) return;
    }
    if (!refresh && !_hasMore) return;
    final f = _doLoad(refresh: refresh);
    _inflight = f;
    await f;
  }

  Future<void> _doLoad({required bool refresh}) async {
    if (refresh) {
      _cursor = null;
      _cursorId = null;
      _hasMore = true;
      // Хуучин дата байвал skeleton flash хийхгүй — RefreshIndicator л хангалттай
      if (state.valueOrNull == null) state = const AsyncValue.loading();
    }
    _loading = true;
    isFetching.value = true;
    if (pageError.value) pageError.value = false;

    try {
      final userId = SupabaseService.currentUser?.id;
      List<Map<String, dynamic>> rows;

      if (userId != null) {
        // RPC: cursor (keyset) — offset scan байхгүй, давхардахгүй
        final data = await SupabaseService.client.rpc(
          'get_discovery_feed',
          params: {
            'p_following': followingOnly,
            'p_limit': AppConstants.feedPageSize,
            'p_before': _cursor?.toIso8601String(),
            'p_before_id': _cursorId,
          },
        );
        rows = (data as List).cast<Map<String, dynamic>>();
      } else {
        if(followingOnly){
          if(mounted){state=const AsyncValue.data([]);_hasMore=false;hasMore.value=false;}
          return;
        }
        // Fallback: plain query with cursor
        var q = SupabaseService.client.from('posts').select(
            '*, profiles!user_id (id, username, avatar_url, is_verified)');
        if (_cursor != null) {
          q = q.lt('created_at', _cursor!.toIso8601String());
        }
        final data = await q
            .order('created_at', ascending: false)
            .limit(AppConstants.feedPageSize);
        rows = (data as List).cast<Map<String, dynamic>>();
      }

      final fetched = rows.map((j) => Post.fromJson(j)).toList();
      if (!mounted) return;
      _hasMore = fetched.length == AppConstants.feedPageSize;
      if (fetched.isNotEmpty) { _cursor = fetched.last.createdAt; _cursorId = fetched.last.id; }

      // Давхардлаас сэргийлэх (cursor хилийн ижил timestamp edge case)
      final existing = refresh ? <Post>[] : (state.valueOrNull ?? []);
      final seen = existing.map((p) => p.id).toSet();
      final merged = [...existing, ...fetched.where((p) => seen.add(p.id))];

      state = AsyncValue.data(merged);
      hasMore.value = _hasMore;
    } catch (e, st) {
      if (!mounted) return;
      if (state.valueOrNull == null) {
        // Анхны ачаалал бүтэлгүйтвэл бүтэн error state
        state = AsyncValue.error(e, st);
      } else {
        // Дата хэвээр үлдээж, footer дээр retry товч харуулна
        pageError.value = true;
      }
    } finally {
      _loading = false;
      if (mounted) isFetching.value = false;
    }
  }

  // ── Optimistic like toggle (фийдэд байгаа пост) ─────────────────────────────
  /// true = амжилттай, false = DB бичилт бүтэлгүйтэж rollback хийсэн
  Future<bool> toggleLike(String postId, {bool? currentlyLiked}) async {
    final user = SupabaseService.currentUser;
    if (user == null || !mounted || !_liking.add(postId)) return false;

    final current = List<Post>.from(state.valueOrNull ?? []);
    final idx = current.indexWhere((p) => p.id == postId);
    if (idx == -1) {
      _liking.remove(postId);
      return false;
    }

    final post = current[idx];
    // Details may have a fresher snapshot than the already-loaded feed.
    final nowLiked = !(currentlyLiked ?? post.isLikedByMe);
    final delta = post.isLikedByMe == nowLiked ? 0 : (nowLiked ? 1 : -1);
    final count = post.likesCount + delta;

    // Optimistic update
    current[idx] = post.copyWith(
      isLikedByMe: nowLiked,
      likesCount: count < 0 ? 0 : count,
    );
    state = AsyncValue.data(current);

    try {
      await _writeLike(user.id, postId, nowLiked);
      return true;
    } catch (_) {
      if (!mounted) return false;
      // Rollback
      final rollback = List<Post>.from(state.valueOrNull ?? []);
      final i = rollback.indexWhere((p) => p.id == postId);
      if (i != -1) {
        rollback[i] = rollback[i].copyWith(
          isLikedByMe: post.isLikedByMe,
          likesCount: post.likesCount,
        );
      }
      state = AsyncValue.data(rollback);
      return false;
    } finally {
      _liking.remove(postId);
    }
  }

  // ── Like toggle by id — фийдэд байхгүй пост дээр ч DB бичилт хийнэ ─────────
  /// Post detail гэх мэт фийдийн гаднаас нээгдсэн постод хэрэглэнэ.
  /// true = амжилттай (caller optimistic state-ээ хадгална), false = rollback хий.
  Future<bool> toggleLikeById(String postId, bool currentlyLiked) async {
    final user = SupabaseService.currentUser;
    if (user == null || !mounted) return false;

    // Фийдэд байвал optimistic toggle (feed картууд ч мөн шинэчлэгдэнэ)
    if ((state.valueOrNull ?? []).any((p) => p.id == postId)) {
      return toggleLike(postId, currentlyLiked: currentlyLiked);
    }
    // Фийдэд байхгүй — DB рүү шууд бичнэ
    if (!_liking.add(postId)) return false;
    try {
      await _writeLike(user.id, postId, !currentlyLiked);
      return true;
    } catch (_) {
      return false;
    } finally {
      _liking.remove(postId);
    }
  }
  void syncLike(Post post){
    syncLikeState(post.id, post.isLikedByMe, post.likesCount);
  }
  void syncLikeState(String id, bool liked, int count) {
    if(!mounted||!state.hasValue)return;
    state=AsyncValue.data(state.value!.map((p)=>p.id==id?p.copyWith(isLikedByMe:liked,likesCount:count<0?0:count):p).toList());
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
    if (user == null) throw StateError('Нэвтэрнэ үү');
    final trimmed = caption.trim();
    try {
      await SupabaseService.client
          .from('posts')
          .update({'caption': trimmed})
          .eq('id', postId)
          .eq('user_id', user.id)
          .select('id')
          .single();
    } catch (_) {
      rethrow;
    }
    if (!mounted) return;
    final list = (state.valueOrNull ?? [])
        .map((p) => p.id == postId ? p.copyWith(caption: trimmed) : p)
        .toList();
    state = AsyncValue.data(list);
  }

  // ── Delete own post ─────────────────────────────────────────────────────────
  /// Блоклосон хэрэглэгчийн бүх постыг feed-ээс шууд арилгана
  /// (бүтэн feed дахин татахгүй).
  void removeAuthor(String userId) {
    final cur = state.valueOrNull;
    if (cur == null) return;
    state = AsyncValue.data(cur.where((p) => p.userId != userId).toList());
  }

  /// Өөр газар (профайлын grid) устгасан постыг feed-ээс арилгана.
  void removeLocal(String postId) {
    final cur = state.valueOrNull;
    if (cur == null) return;
    state = AsyncValue.data(cur.where((p) => p.id != postId).toList());
  }

  Future<bool> deletePost(String postId) async {
    final user = SupabaseService.currentUser;
    if (user == null) return false;
    try {
      await SupabaseService.client
          .from('posts')
          .delete()
          .eq('id', postId)
          .eq('user_id', user.id)
          .select('id')
          .single();
    } catch (_) {
      return false; // устгаж чадсангүй
    }
    if (!mounted) return true;
    final updated =
        (state.valueOrNull ?? []).where((p) => p.id != postId).toList();
    state = AsyncValue.data(updated);
    return true;
  }
}

final feedProvider =
    StateNotifierProvider<FeedNotifier, AsyncValue<List<Post>>>((ref) {
  ref.watch(sessionUserIdProvider);
  ref.watch(socialVersionProvider);
  return FeedNotifier();
});
final followingFeedProvider=StateNotifierProvider<FeedNotifier,AsyncValue<List<Post>>>((ref) {
  ref.watch(sessionUserIdProvider);
  ref.watch(socialVersionProvider);
  return FeedNotifier(followingOnly:true);
});
