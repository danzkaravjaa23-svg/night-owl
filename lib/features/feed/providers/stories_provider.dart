import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/services/supabase_service.dart';
import '../../../models/story.dart';
import '../../../models/user_profile.dart';

// ─── Active stories grouped by user ──────────────────────────────────────────
final storiesProvider = FutureProvider<List<StoryRing>>((ref) async {
  // Зөвхөн дагадаг хүмүүс + өөрийн story (500к scale дээр global fetch болохгүй)
  final me = SupabaseService.currentUser?.id;

  List<String> targetIds = [];
  if (me != null) {
    try {
      final f = await SupabaseService.client
          .from('follows')
          .select('following_id')
          .eq('follower_id', me);
      targetIds = (f as List)
          .map((e) => e['following_id'].toString())
          .toList();
    } catch (_) {}
    targetIds.add(me); // өөрийн story үргэлж багтана
  }

  var query = SupabaseService.client
      .from('stories')
      .select('*, profiles!user_id (id, username, avatar_url, is_verified), venues!venue_id (name)')
      // Хугацаа дууссан story-г сервер талд шүүнэ (200 мөрийн limit үрэхгүй)
      .gt('expires_at', DateTime.now().toUtc().toIso8601String());
  if (targetIds.isNotEmpty) query = query.inFilter('user_id', targetIds);

  final data = await query
      .order('created_at', ascending: false)
      .limit(200);

  final stories = (data as List)
      .cast<Map<String, dynamic>>()
      .map((j) => Story.fromJson(j))
      .where((s) => !s.isExpired)
      .toList();

  // Which stories has the current user already seen?
  final Set<String> viewedIds = {};
  if (me != null) {
    try {
      final views = await SupabaseService.client
          .from('story_views')
          .select('story_id')
          .eq('viewer_id', me);
      for (final v in (views as List)) {
        final id = v['story_id'];
        if (id != null) viewedIds.add(id.toString());
      }
    } catch (_) {}
  }

  // Group by userId, put own stories first
  final Map<String, List<Story>> grouped = {};
  for (final s in stories) {
    grouped.putIfAbsent(s.userId, () => []).add(s);
  }

  // Build rings
  final rings = grouped.entries.map((e) {
    final userId = e.key;
    final userStories = e.value..sort((a, b) => a.createdAt.compareTo(b.createdAt));
    final author = userStories.first.author ??
        UserProfile(id: userId, username: 'User');
    return StoryRing(
      userId:           userId,
      author:           author,
      stories:          userStories,
      hasUnseenStories: userStories.any((s) => !viewedIds.contains(s.id)),
    );
  }).toList();

  // Own story first
  rings.sort((a, b) {
    if (a.userId == me) return -1;
    if (b.userId == me) return 1;
    return b.latest.createdAt.compareTo(a.latest.createdAt);
  });

  return rings;
});

// ─── Story service ────────────────────────────────────────────────────────────
class StoryService {
  static Future<String?> createStory({
    required String mediaUrl,
    String mediaType = 'image',
    String? caption,
    int duration = 5,
    String? venueId,
    List<String> mentions = const [],
    String? musicUrl,
    String? musicTitle,
    String? musicArtist,
  }) async {
    final user = SupabaseService.currentUser;
    if (user == null) return 'Нэвтэрнэ үү';
    try {
      await SupabaseService.client.from('stories').insert({
        'user_id':    user.id,
        'media_url':  mediaUrl,
        'media_type': mediaType,
        'caption':    caption,
        // Видеоны бодит урт (create талд хэмжсэн), зураг 5с
        'duration':   duration.clamp(1, 120),
        if (venueId != null) 'venue_id': venueId,
        if (mentions.isNotEmpty) 'mentions': mentions,
        if (musicUrl != null) 'music_url': musicUrl,
        if (musicTitle != null) 'music_title': musicTitle,
        if (musicArtist != null) 'music_artist': musicArtist,
      });
      return null;
    } catch (e) {
      return e.toString();
    }
  }

  static Future<void> markViewed(String storyId) async {
    final me = SupabaseService.currentUser?.id;
    if (me == null) return;
    try {
      await SupabaseService.client.from('story_views').upsert({
        'story_id':  storyId,
        'viewer_id': me,
      }, onConflict: 'story_id, viewer_id');
      // Increment view_count
      await SupabaseService.client.rpc('increment_story_views',
          params: {'story_id': storyId}).catchError((_) => null);
    } catch (_) {}
  }

  /// Тухайн story-г одоогийн хэрэглэгч лайк дарсан эсэх
  static Future<bool> isLiked(String storyId) async {
    final me = SupabaseService.currentUser?.id;
    if (me == null) return false;
    try {
      final rows = await SupabaseService.client
          .from('story_likes')
          .select('story_id')
          .eq('story_id', storyId)
          .eq('user_id', me)
          .limit(1);
      return (rows as List).isNotEmpty;
    } catch (_) {
      return false;
    }
  }

  /// Story лайк toggle (like=true → нэмэх, false → хасах).
  /// Амжилттай бол true — UI optimistic төлөвөө буцаахад ашиглана.
  static Future<bool> toggleLike(String storyId, bool like) async {
    final me = SupabaseService.currentUser?.id;
    if (me == null) return false;
    try {
      if (like) {
        await SupabaseService.client.from('story_likes').upsert({
          'story_id': storyId,
          'user_id':  me,
        }, onConflict: 'story_id, user_id');
      } else {
        await SupabaseService.client
            .from('story_likes')
            .delete()
            .eq('story_id', storyId)
            .eq('user_id', me);
      }
      return true;
    } catch (_) {
      return false;
    }
  }
}
