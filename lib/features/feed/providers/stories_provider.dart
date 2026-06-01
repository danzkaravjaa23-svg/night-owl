import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/services/supabase_service.dart';
import '../../../models/story.dart';
import '../../../models/user_profile.dart';

// ─── Active stories grouped by user ──────────────────────────────────────────
final storiesProvider = FutureProvider<List<StoryRing>>((ref) async {
  // Fetch stories from users I follow + my own
  final me = SupabaseService.currentUser?.id;

  final data = await SupabaseService.client
      .from('stories')
      .select('*, profiles!user_id (id, username, avatar_url, is_verified), venues!venue_id (name)')
      .order('created_at', ascending: false)
      .limit(200);

  final stories = (data as List)
      .cast<Map<String, dynamic>>()
      .map((j) => Story.fromJson(j))
      .where((s) => !s.isExpired)
      .toList();

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
      hasUnseenStories: true, // TODO: check story_views table
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
  }) async {
    final user = SupabaseService.currentUser;
    if (user == null) return 'Нэвтэрнэ үү';
    try {
      await SupabaseService.client.from('stories').insert({
        'user_id':    user.id,
        'media_url':  mediaUrl,
        'media_type': mediaType,
        'caption':    caption,
        'duration':   duration,
        if (venueId != null) 'venue_id': venueId,
        if (mentions.isNotEmpty) 'mentions': mentions,
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
}
