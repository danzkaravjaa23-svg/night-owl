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

  Future<void> toggle() async {
    final me = SupabaseService.currentUser?.id;
    if (me == null) return;
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
    } catch (_) {
      // Rollback
      state = AsyncValue.data(current);
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
  /// Followers list (who follows targetUserId)
  static Future<List<Map<String, dynamic>>> getFollowers(
      String userId, {int limit = 30}) async {
    final data = await SupabaseService.client
        .from('follows')
        .select('follower_id, profiles!follower_id (id, username, avatar_url, is_verified)')
        .eq('following_id', userId)
        .order('created_at', ascending: false)
        .limit(limit);
    return (data as List).cast<Map<String, dynamic>>();
  }

  /// Following list (who targetUserId follows)
  static Future<List<Map<String, dynamic>>> getFollowing(
      String userId, {int limit = 30}) async {
    final data = await SupabaseService.client
        .from('follows')
        .select('following_id, profiles!following_id (id, username, avatar_url, is_verified)')
        .eq('follower_id', userId)
        .order('created_at', ascending: false)
        .limit(limit);
    return (data as List).cast<Map<String, dynamic>>();
  }
}
