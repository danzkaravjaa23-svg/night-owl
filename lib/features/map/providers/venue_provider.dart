import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/services/supabase_service.dart';
import '../../../models/venue.dart';
import '../../../models/event.dart';

// ─── All venues — нэг удаагийн fetch (realtime биш) ───
// Venue ховор өөрчлөгддөг тул table-wide realtime sub шаардлагагүй.
// (Шинэчлэхдээ ref.invalidate(venuesProvider) дуудна.)
final venuesProvider = FutureProvider<List<Venue>>((ref) async {
  final data = await SupabaseService.client
      .from('venues')
      .select()
      .order('name')
      .limit(2000); // 700+ venue-г бүгдийг харуулна
  return (data as List)
      .map((j) => Venue.fromJson(j as Map<String, dynamic>))
      .toList();
});

// ─── Одоогийн хэрэглэгч venue эзэмшдэг эсэх (Discovery контент оруулах эрх) ───
final isVenueOwnerProvider = FutureProvider<bool>((ref) async {
  final me = SupabaseService.currentUser?.id;
  if (me == null) return false;
  try {
    final r = await SupabaseService.client
        .from('venues').select('id').eq('owner_id', me).limit(1).maybeSingle();
    return r != null;
  } catch (_) {
    return false;
  }
});

// ─── Single venue detail ───
final venueDetailProvider =
    FutureProvider.family<Venue?, String>((ref, venueId) async {
  final data = await SupabaseService.client
      .from('venues')
      .select()
      .eq('id', venueId)
      .maybeSingle();
  return data != null ? Venue.fromJson(data) : null;
});

// ─── Today's events for a venue ───
final venueEventsProvider =
    FutureProvider.family<List<VenueEvent>, String>((ref, venueId) async {
  final today = DateTime.now();
  final start = DateTime(today.year, today.month, today.day);
  final end   = start.add(const Duration(days: 1));

  final data = await SupabaseService.client
      .from('events')
      .select()
      .eq('venue_id', venueId)
      .gte('starts_at', start.toIso8601String())
      .lt('starts_at', end.toIso8601String())
      .order('starts_at');

  return (data as List)
      .map((j) => VenueEvent.fromJson(j as Map<String, dynamic>))
      .toList();
});

// ─── Check-in ───
class CheckInNotifier extends StateNotifier<String?> {
  CheckInNotifier() : super(null);

  /// Returns checked-in venue id, or null
  Future<void> checkIn(String venueId) async {
    final user = SupabaseService.currentUser;
    if (user == null) return;

    await SupabaseService.client.from('checkins').upsert({
      'user_id':    user.id,
      'venue_id':   venueId,
      'created_at': DateTime.now().toIso8601String(),
      'expires_at': DateTime.now()
          .add(const Duration(hours: 4))
          .toIso8601String(),
    }, onConflict: 'user_id, venue_id');

    state = venueId;
  }

  Future<void> checkOut() async {
    final user = SupabaseService.currentUser;
    if (user == null) return;
    await SupabaseService.client
        .from('checkins')
        .delete()
        .eq('user_id', user.id);
    state = null;
  }
}

final checkInProvider =
    StateNotifierProvider<CheckInNotifier, String?>(
        (_) => CheckInNotifier());

// ─── Search venues ───
final venueSearchProvider =
    FutureProvider.family<List<Venue>, String>((ref, query) async {
  if (query.isEmpty) return [];
  final data = await SupabaseService.client
      .from('venues')
      .select()
      .ilike('name', '%$query%')
      .limit(20);
  return (data as List)
      .map((j) => Venue.fromJson(j as Map<String, dynamic>))
      .toList();
});
