import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/services/supabase_service.dart';

/// Идэвхтэй live-ийн нэг мөр
class LiveItem {
  final String id;
  final String userId;
  final String title;
  final int viewers;
  final String username;
  final String? avatarUrl;
  final String? venueName;
  const LiveItem({
    required this.id,
    required this.userId,
    required this.title,
    required this.viewers,
    required this.username,
    this.avatarUrl,
    this.venueName,
  });

  /// Газрын нэр байвал түүгээр, эс бол хэрэглэгчийн нэрээр
  String get displayName => (venueName != null && venueName!.isNotEmpty)
      ? venueName! : username;
}

/// Идэвхтэй (is_live=true) live-ууд — discovery rail-д харагдана
final activeLivesProvider = FutureProvider<List<LiveItem>>((ref) async {
  final client = SupabaseService.client;
  // Зөвхөн сүүлийн 6 цагт эхэлсэн live (stale stream-ийг нуух)
  final since = DateTime.now().subtract(const Duration(hours: 6)).toIso8601String();
  final lives = await client
      .from('live_streams')
      .select('id, user_id, title, viewer_count, started_at, venue_id')
      .eq('is_live', true)
      .gte('started_at', since)
      .order('started_at', ascending: false)
      .limit(20);
  final list = (lives as List).cast<Map<String, dynamic>>();
  if (list.isEmpty) return [];

  final ids = list.map((e) => e['user_id'] as String).toSet().toList();
  final profs = await client
      .from('profiles')
      .select('id, username, avatar_url')
      .inFilter('id', ids);
  final pmap = {
    for (final p in (profs as List).cast<Map<String, dynamic>>())
      p['id'] as String: p
  };

  // Газрын нэрс
  final venueIds = list.map((e) => e['venue_id']).whereType<String>().toSet().toList();
  Map<String, String> vmap = {};
  if (venueIds.isNotEmpty) {
    final vs = await client.from('venues').select('id, name').inFilter('id', venueIds);
    vmap = { for (final v in (vs as List).cast<Map<String, dynamic>>())
      v['id'] as String: v['name'] as String };
  }

  return list.map((l) {
    final p = pmap[l['user_id']];
    return LiveItem(
      id:        l['id'] as String,
      userId:    l['user_id'] as String,
      title:     (l['title'] as String?)?.trim().isNotEmpty == true
          ? l['title'] as String : 'Live',
      viewers:   l['viewer_count'] as int? ?? 0,
      username:  p?['username'] as String? ?? 'User',
      avatarUrl: p?['avatar_url'] as String?,
      venueName: l['venue_id'] != null ? vmap[l['venue_id']] : null,
    );
  }).toList();
});
