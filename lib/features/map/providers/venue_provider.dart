import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/services/supabase_service.dart';
import '../../../models/venue.dart';

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

// ─── Check-in ───
// State = одоо check-in хийсэн venue id (null = хаана ч биш).
class CheckInNotifier extends StateNotifier<String?> {
  CheckInNotifier() : super(null);
  bool _loaded = false;

  /// Идэвхтэй check-in-ээ DB-ээс сэргээнэ (session-д нэг л удаа хангалттай)
  Future<void> loadCurrent() async {
    if (_loaded) return;
    _loaded = true;
    final user = SupabaseService.currentUser;
    if (user == null) return;
    try {
      final r = await SupabaseService.client
          .from('checkins')
          .select('venue_id')
          .eq('user_id', user.id)
          .gt('expires_at', DateTime.now().toUtc().toIso8601String())
          .order('created_at', ascending: false)
          .limit(1)
          .maybeSingle();
      if (mounted) state = r?['venue_id'] as String?;
    } catch (_) {
      // чимээгүй — дараагийн check-in үед төлөв зөв болно
    }
  }

  /// null = амжилт, бусад нь хэрэглэгчид харуулах алдааны мессеж
  Future<String?> checkIn(String venueId) async {
    final user = SupabaseService.currentUser;
    if (user == null) return 'Нэвтэрнэ үү';
    try {
      await SupabaseService.client.from('checkins').upsert({
        'user_id':    user.id,
        'venue_id':   venueId,
        'created_at': DateTime.now().toUtc().toIso8601String(),
        'expires_at': DateTime.now().toUtc()
            .add(const Duration(hours: 4))
            .toIso8601String(),
      }, onConflict: 'user_id, venue_id');
      if (mounted) state = venueId;
      return null;
    } catch (_) {
      return 'Бүртгэж чадсангүй. Дахин оролдоно уу';
    }
  }

  /// Тухайн venue-гээс гарах (зөвхөн энэ venue-ийн мөрийг устгана)
  Future<String?> checkOut(String venueId) async {
    final user = SupabaseService.currentUser;
    if (user == null) return 'Нэвтэрнэ үү';
    try {
      await SupabaseService.client
          .from('checkins')
          .delete()
          .match({'user_id': user.id, 'venue_id': venueId});
      if (mounted && state == venueId) state = null;
      return null;
    } catch (_) {
      return 'Гаргаж чадсангүй. Дахин оролдоно уу';
    }
  }
}

final checkInProvider =
    StateNotifierProvider<CheckInNotifier, String?>(
        (_) => CheckInNotifier());
