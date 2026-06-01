import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/services/supabase_service.dart';

class EventItem {
  final String id;
  final String title;
  final String? description;
  final String? coverUrl;
  final DateTime startsAt;
  final int price;
  final String? venueName;
  final String? organizerName;
  const EventItem({
    required this.id,
    required this.title,
    this.description,
    this.coverUrl,
    required this.startsAt,
    this.price = 0,
    this.venueName,
    this.organizerName,
  });
}

/// Удахгүй болох event-ууд (feed-д харагдана)
final upcomingEventsProvider = FutureProvider<List<EventItem>>((ref) async {
  final client = SupabaseService.client;
  final now = DateTime.now().subtract(const Duration(hours: 3)).toIso8601String();
  final data = await client
      .from('events')
      .select('id, title, description, cover_url, starts_at, price, venue_id, organizer_id')
      .gte('starts_at', now)
      .order('starts_at', ascending: true)
      .limit(30);
  final rows = (data as List).cast<Map<String, dynamic>>();
  if (rows.isEmpty) return [];

  final venueIds = rows.map((r) => r['venue_id']).whereType<String>().toSet().toList();
  final orgIds = rows.map((r) => r['organizer_id']).whereType<String>().toSet().toList();

  Map<String, String> vmap = {};
  Map<String, String> omap = {};
  if (venueIds.isNotEmpty) {
    final vs = await client.from('venues').select('id, name').inFilter('id', venueIds);
    vmap = { for (final v in (vs as List).cast<Map<String, dynamic>>())
      v['id'] as String: v['name'] as String };
  }
  if (orgIds.isNotEmpty) {
    final os = await client.from('profiles').select('id, username').inFilter('id', orgIds);
    omap = { for (final o in (os as List).cast<Map<String, dynamic>>())
      o['id'] as String: o['username'] as String? ?? '' };
  }

  return rows.map((r) => EventItem(
    id: r['id'] as String,
    title: r['title'] as String? ?? 'Event',
    description: r['description'] as String?,
    coverUrl: r['cover_url'] as String?,
    startsAt: DateTime.parse(r['starts_at'] as String),
    price: r['price'] as int? ?? 0,
    venueName: r['venue_id'] != null ? vmap[r['venue_id']] : null,
    organizerName: r['organizer_id'] != null ? omap[r['organizer_id']] : null,
  )).toList();
});
