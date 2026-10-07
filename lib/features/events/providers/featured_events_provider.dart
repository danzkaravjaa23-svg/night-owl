import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/services/supabase_service.dart';
import '../../auth/providers/auth_provider.dart';
import 'event_provider.dart';

/// An explicit server-side selection, never a property supplied by an event's
/// organizer. Smaller ranks appear first; equal ranks use the event start time.
class FeaturedEventSelection {
  final String eventId;
  final int rank;

  const FeaturedEventSelection({required this.eventId, required this.rank});
}

/// Distinguishes an unapplied migration from an empty selection or a network
/// failure. The UI must not silently substitute ordinary events as featured.
class FeatureEventsUnavailableException implements Exception {
  const FeatureEventsUnavailableException();

  @override
  String toString() => 'Онцгой эвентийн хэсэг түр бэлэн биш байна.';
}

final eventFeatureServiceProvider = Provider<EventFeatureService>(
  (ref) => EventFeatureService(client: SupabaseService.client),
);

final featuredEventsProvider = FutureProvider<List<EventItem>>(
  (ref) => ref.watch(eventFeatureServiceProvider).loadFeatured(),
);

final adminFeaturedEventsProvider =
    FutureProvider<List<FeaturedEventSelection>>(
  (ref) {
    final userId = ref.watch(sessionUserIdProvider);
    if (userId == null) return const [];
    return ref.watch(eventFeatureServiceProvider).loadSelections();
  },
);

class EventFeatureService {
  final SupabaseClient client;

  const EventFeatureService({required this.client});

  Future<dynamic> _rpc(String name, [Map<String, dynamic>? params]) async {
    try {
      return await client.rpc(name, params: params);
    } on PostgrestException catch (error) {
      // Only a missing RPC is a deployment mismatch. Permission/network/query
      // failures must remain failures, rather than looking like an empty rail.
      if (error.code == 'PGRST202' || error.code == '42883') {
        throw const FeatureEventsUnavailableException();
      }
      rethrow;
    }
  }

  Future<List<EventItem>> loadFeatured() async {
    final data = await _rpc('get_featured_events');
    return List<EventItem>.unmodifiable(
      (data as List).cast<Map<String, dynamic>>().map(
            (row) => EventItem(
              id: row['id'] as String,
              title: row['title'] as String,
              description: row['description'] as String?,
              coverUrl: row['cover_url'] as String?,
              startsAt: DateTime.parse(row['starts_at'] as String),
              price: (row['price'] as num?)?.toInt() ?? 0,
              venueName: row['venue_name'] as String?,
              organizerName: row['organizer_name'] as String?,
              attendeeCount: (row['attendee_count'] as num?)?.toInt() ?? 0,
            ),
          ),
    );
  }

  Future<List<FeaturedEventSelection>> loadSelections() async {
    final data = await _rpc('get_admin_featured_events');
    return List<FeaturedEventSelection>.unmodifiable(
      (data as List).cast<Map<String, dynamic>>().map(
            (row) => FeaturedEventSelection(
              eventId: row['event_id'] as String,
              rank: (row['rank'] as num).toInt(),
            ),
          ),
    );
  }

  Future<void> setFeatured(
    String eventId, {
    required bool featured,
    int rank = 0,
  }) async {
    if (rank < 0 || rank > 9999) {
      throw RangeError.range(rank, 0, 9999, 'rank');
    }
    // Authorization is intentionally checked inside the database RPC, not
    // inferred from a potentially stale client profile or an admin-only button.
    await _rpc('set_featured_event', {
      'p_event_id': eventId,
      'p_featured': featured,
      'p_rank': rank,
    });
  }
}
