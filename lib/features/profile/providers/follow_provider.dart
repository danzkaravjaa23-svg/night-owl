import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/services/supabase_service.dart';

// ─── Is following a user ──────────────────────────────────────────────────────
final isFollowingProvider =
    FutureProvider.family<bool, String>((ref, targetUserId) async {
  final me = SupabaseService.currentUser?.id;
  if (me == null || me == targetUserId) return false;

  final data = await SupabaseService.client
      .from('follows')
      .select('id')
      .eq('follower_id', me)
      .eq('following_id', targetUserId)
      .maybeSingle();

  return data != null;
});

// ─── Follow state notifier (optimistic) ──────────────────────────────────────
class FollowNotifier extends StateNotifier<AsyncValue<bool>> {
  final String targetUserId;

  /// toggle() бүтэлгүйтэж rollback хийсэн бол UI-д toast харуулах callback.
  /// (Провайдер өөрөө snackbar харуулж чадахгүй тул дээд давхарга бүртгэнэ.)
  void Function()? onFailure;

  FollowNotifier(this.targetUserId) : super(const AsyncValue.loading()) {
    _init();
  }

  Future<void> _init() async {
    final me = SupabaseService.currentUser?.id;
    if (me == null || me == targetUserId) {
      state = const AsyncValue.data(false);
      return;
    }
    try {
      final data = await SupabaseService.client
          .from('follows')
          .select('id')
          .eq('follower_id', me)
          .eq('following_id', targetUserId)
          .maybeSingle();
      state = AsyncValue.data(data != null);
    } catch (e, st) {
      state = AsyncValue.error(e, st);
    }
  }

  /// Дагах/болих. Амжилттай бол true, бүтэлгүйтэж rollback хийвэл false буцаана.
  Future<bool> toggle() async {
    final me = SupabaseService.currentUser?.id;
    if (me == null) return false;
    final current = state.value ?? false;

    // Optimistic
    state = AsyncValue.data(!current);

    try {
      if (!current) {
        await SupabaseService.client.from('follows').insert({
          'follower_id':  me,
          'following_id': targetUserId,
        });
      } else {
        await SupabaseService.client
            .from('follows')
            .delete()
            .eq('follower_id', me)
            .eq('following_id', targetUserId);
      }
      return true;
    } catch (_) {
      // Rollback + UI-д мэдэгдэх
      state = AsyncValue.data(current);
      onFailure?.call();
      return false;
    }
  }
}

final followProvider =
    StateNotifierProvider.family<FollowNotifier, AsyncValue<bool>, String>(
        (ref, userId) => FollowNotifier(userId));

// ─── Follower / following counts ─────────────────────────────────────────────
class FollowCounts {
  final int followers;
  final int following;
  const FollowCounts({this.followers = 0, this.following = 0});
}

final followCountsProvider =
    FutureProvider.family<FollowCounts, String>((ref, userId) async {
  final data = await SupabaseService.client
      .from('profiles')
      .select('followers_count, following_count')
      .eq('id', userId)
      .maybeSingle();

  if (data == null) return const FollowCounts();
  final d = data;
  return FollowCounts(
    followers: d['followers_count'] as int? ?? 0,
    following: d['following_count'] as int? ?? 0,
  );
});

// ─── Follow service ───────────────────────────────────────────────────────────
class FollowService {
  /// Нэст хийсэн `profiles` мөрийг цэвэр map болгож задлана
  static List<Map<String, dynamic>> _flatten(List data) {
    final out = <Map<String, dynamic>>[];
    for (final row in data) {
      final p = row['profiles'];
      if (p is Map) out.add(Map<String, dynamic>.from(p));
    }
    return out;
  }

  /// Followers list (who follows targetUserId)
  static Future<List<Map<String, dynamic>>> getFollowers(
      String userId, {int limit = 100}) async {
    final data = await SupabaseService.client
        .from('follows')
        .select('follower_id, created_at, profiles!follower_id (id, username, avatar_url, is_verified, full_name)')
        .eq('following_id', userId)
        .order('created_at', ascending: false)
        .limit(limit);
    return _flatten(data as List);
  }

  /// Following list (who targetUserId follows)
  static Future<List<Map<String, dynamic>>> getFollowing(
      String userId, {int limit = 100}) async {
    final data = await SupabaseService.client
        .from('follows')
        .select('following_id, created_at, profiles!following_id (id, username, avatar_url, is_verified, full_name)')
        .eq('follower_id', userId)
        .order('created_at', ascending: false)
        .limit(limit);
    return _flatten(data as List);
  }

  /// Миний дагаж буй хүмүүсийн id-ууд (жагсаалтад товч зурахад)
  static Future<Set<String>> myFollowingIds() async {
    final me = SupabaseService.currentUser?.id;
    if (me == null) return {};
    final data = await SupabaseService.client
        .from('follows')
        .select('following_id')
        .eq('follower_id', me);
    return {for (final r in (data as List)) r['following_id'] as String};
  }

  static Future<void> follow(String userId) async {
    final me = SupabaseService.currentUser?.id;
    if (me == null || me == userId) return;
    await SupabaseService.client.from('follows').insert({
      'follower_id': me, 'following_id': userId,
    });
  }

  static Future<void> unfollow(String userId) async {
    final me = SupabaseService.currentUser?.id;
    if (me == null) return;
    await SupabaseService.client.from('follows')
        .delete()
        .eq('follower_id', me)
        .eq('following_id', userId);
  }
}
