import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/services/supabase_service.dart';
import '../../auth/providers/auth_provider.dart';
import '../../../models/venue.dart';

// ─── All venues — нэг удаагийн fetch (realtime биш) ───
// Venue ховор өөрчлөгддөг тул table-wide realtime sub шаардлагагүй.
// (Шинэчлэхдээ ref.invalidate(venuesProvider) дуудна.)
final venuesProvider = FutureProvider<List<Venue>>((ref) async {
  final data = await SupabaseService.client
      .from('venues')
      .select()
      .order('name')
      .limit(2000);
  return (data as List)
      .map((j) => Venue.fromJson(j as Map<String, dynamic>))
      .where((venue) => !venue.isDemo)
      .toList();
});

// ─── Одоогийн хэрэглэгч venue эзэмшдэг эсэх (Discovery контент оруулах эрх) ───
final isVenueOwnerProvider = FutureProvider<bool>((ref) async {
  final me = ref.watch(sessionUserIdProvider);
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
  bool _busy = false;
  int _request = 0;
  Timer? _expiry;

  void _setCurrent(String? venueId, DateTime? expiresAt) {
    _expiry?.cancel();
    if (!mounted) return;
    if (venueId == null || expiresAt == null || !expiresAt.isAfter(DateTime.now().toUtc())) {
      state = null;
      return;
    }
    state = venueId;
    _expiry = Timer(expiresAt.difference(DateTime.now().toUtc()), () {
      if (mounted) { state = null; _loaded = false; }
    });
  }

  /// Идэвхтэй check-in-ээ DB-ээс сэргээнэ (session-д нэг л удаа хангалттай)
  Future<void> loadCurrent() async {
    if (_loaded || _busy) return;
    final user = SupabaseService.currentUser;
    if (user == null) return;
    final request = ++_request;
    try {
      final r = await SupabaseService.client
          .from('checkins')
          .select('venue_id, expires_at')
          .eq('user_id', user.id)
          .gt('expires_at', DateTime.now().toUtc().toIso8601String())
          .order('created_at', ascending: false)
          .limit(1)
          .maybeSingle();
      if (mounted && request == _request) {
        _setCurrent(r?['venue_id'] as String?, DateTime.tryParse(r?['expires_at']?.toString() ?? ''));
        _loaded = true;
      }
    } catch (_) {
      // чимээгүй — дараагийн check-in үед төлөв зөв болно
    }
  }

  /// null = амжилт, бусад нь хэрэглэгчид харуулах алдааны мессеж
  Future<String?> checkIn(String venueId) async {
    final user = SupabaseService.currentUser;
    if (user == null) return 'Нэвтэрнэ үү';
    if (_busy) return 'Түр хүлээнэ үү';
    _busy = true;
    ++_request;
    try {
      // Server transaction serializes per user and expires any previous venue.
      final result = await SupabaseService.client.rpc('check_in_venue', params: {'p_venue_id': venueId});
      final row = (result as List).single as Map;
      final expiry = DateTime.tryParse(row['expires_at']?.toString() ?? '');
      if (expiry == null || row['venue_id'] != venueId) throw StateError('Invalid check-in response');
      if (mounted) { _setCurrent(venueId, expiry); _loaded = true; }
      return null;
    } catch (_) {
      return 'Бүртгэж чадсангүй. Дахин оролдоно уу';
    } finally { _busy = false; }
  }

  /// Тухайн venue-гээс гарах (зөвхөн энэ venue-ийн мөрийг устгана)
  Future<String?> checkOut(String venueId) async {
    final user = SupabaseService.currentUser;
    if (user == null) return 'Нэвтэрнэ үү';
    if (_busy) return 'Түр хүлээнэ үү';
    _busy = true;
    ++_request;
    try {
      await SupabaseService.client
          .from('checkins')
          .delete()
          .match({'user_id': user.id, 'venue_id': venueId});
      if (mounted && state == venueId) _setCurrent(null, null);
      return null;
    } catch (_) {
      return 'Гаргаж чадсангүй. Дахин оролдоно уу';
    } finally { _busy = false; }
  }

  @override
  void dispose() { _expiry?.cancel(); super.dispose(); }
}

final checkInProvider =
    StateNotifierProvider<CheckInNotifier, String?>(
        (ref) {
          ref.watch(sessionUserIdProvider);
          return CheckInNotifier();
        });
