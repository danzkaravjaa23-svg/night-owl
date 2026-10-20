import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../core/services/supabase_service.dart';
import '../../../core/widgets/network_video.dart' show isVideoUrl;
import '../../auth/providers/auth_provider.dart';
import '../../discovery/services/discovery_service.dart';

/// Filter before the limit, so a run of recent photo posts cannot hide videos.
/// Legacy live recordings sometimes have media_type=image; their URL still
/// identifies them. Validate those matches after fetching as well.
class ReelsRepository {
  final SupabaseClient client;
  const ReelsRepository(this.client);

  static const _columns =
      'id, user_id, caption, media_url, media_urls, media_type, '
      'likes_count, comments_count, created_at, venue_ref, '
      'venue_catalog!venue_ref (name), '
      'profiles!user_id (username, avatar_url)';
  static const _videoFilter = 'media_type.eq.video,'
      'media_url.ilike.%.mp4*,media_url.ilike.%.webm*,'
      'media_url.ilike.%.mov*,media_url.ilike.%.m4v*,'
      'media_url.ilike.%.avi*,media_url.ilike.%.mkv*';

  static Map<String, dynamic>? normalize(Map<String, dynamic> post) {
    final url = post['media_url'] as String?;
    final alternatives = (post['media_urls'] as List?)?.whereType<String>() ??
        const Iterable<String>.empty();
    final candidates = [if (url != null) url, ...alternatives];
    String? media;
    String? typedFallback;
    for (final candidate in candidates) {
      final uri = Uri.tryParse(candidate);
      if (uri == null ||
          !uri.hasAuthority ||
          (uri.scheme != 'https' && uri.scheme != 'http')) {
        continue;
      }
      if (isVideoUrl(candidate)) {
        media = candidate;
        break;
      }
      // A carousel may carry its photo cover in media_url. Prefer an actual
      // video from media_urls before considering an opaque, typed video URL.
      if (post['media_type'] == 'video' &&
          !RegExp(r'\.(avif|bmp|gif|heic|heif|ico|jpe?g|png|svg|webp)$',
                  caseSensitive: false)
              .hasMatch(uri.path)) {
        typedFallback ??= candidate;
      }
    }
    media ??= typedFallback;
    if (media == null || post['id'] is! String || post['user_id'] is! String) {
      return null;
    }
    return {...post, 'media_url': media};
  }

  Future<List<Map<String, dynamic>>> load() async {
    final rows = await client
        .from('posts')
        .select(_columns)
        .or(_videoFilter)
        .order('created_at', ascending: false)
        .order('id', ascending: false)
        .limit(50);
    return rows.map(normalize).whereType<Map<String, dynamic>>().toList();
  }

  Future<List<Map<String, dynamic>>> loadFollowing() async {
    final data =
        await client.rpc('get_following_reels', params: {'p_limit': 50});
    return (data as List)
        .map((row) => normalize(Map<String, dynamic>.from(row as Map)))
        .whereType<Map<String, dynamic>>()
        .toList();
  }

  Future<Map<String, dynamic>?> find(String id) async {
    final row =
        await client.from('posts').select(_columns).eq('id', id).maybeSingle();
    return row == null ? null : normalize(row);
  }
}

final reelsProvider = FutureProvider<List<Map<String, dynamic>>>((ref) async {
  ref.watch(sessionUserIdProvider);
  ref.watch(postsVersionProvider);
  ref.watch(socialVersionProvider);
  return ReelsRepository(SupabaseService.client).load();
});

final followingReelsProvider =
    FutureProvider<List<Map<String, dynamic>>>((ref) async {
  final account = ref.watch(sessionUserIdProvider);
  ref.watch(postsVersionProvider);
  ref.watch(socialVersionProvider);
  if (account == null) return [];
  return ReelsRepository(SupabaseService.client).loadFollowing();
});
