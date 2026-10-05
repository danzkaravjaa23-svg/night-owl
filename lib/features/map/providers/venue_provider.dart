import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/services/supabase_service.dart';
import '../../auth/providers/auth_provider.dart';
import '../../../models/venue.dart';

// ─── All venues — нэг удаагийн fetch (realtime биш) ───
// Venue ховор өөрчлөгддөг тул table-wide realtime sub шаардлагагүй.
// (Шинэчлэхдээ ref.invalidate(venuesProvider) дуудна.)
final venueBackendRowsProvider = FutureProvider<List<Venue>>((ref) async {
  final data = await SupabaseService.client
      .from('venues')
      .select()
      .order('name')
      .limit(2000)
      .timeout(const Duration(seconds: 8));
  return (data as List)
      .map((j) => Venue.fromJson(j as Map<String, dynamic>))
      .where((venue) => !venue.isDemo)
      .toList();
});

/// Source status is separate from content: a bundled catalog is usable even
/// when the community server fails, but that does not imply a successful fetch.
class VenueCatalogStatus {
  final bool communityUnavailable;
  final bool supplementUnavailable;
  final int supplementalCount;
  final DateTime? sourceRetrievedAt;
  const VenueCatalogStatus({
    this.communityUnavailable = false,
    this.supplementUnavailable = false,
    this.supplementalCount = 0,
    this.sourceRetrievedAt,
  });

  String? get notice {
    if (communityUnavailable && supplementUnavailable) {
      return 'Газрын мэдээллийг шинэчилж чадсангүй. Дахин оролдоно уу.';
    }
    if (communityUnavailable) {
      if (supplementUnavailable || supplementalCount == 0) {
        return 'Сервертэй холбогдож чадсангүй. Газрын мэдээлэл одоогоор алга. Дахин оролдоно уу.';
      }
      return 'Сервертэй холбогдож чадсангүй. OpenStreetMap-ийн газрын мэдээллийг харуулж байна.';
    }
    if (supplementUnavailable) {
      return 'OpenStreetMap-ийн нэмэлт мэдээллийг ачаалж чадсангүй.';
    }
    return null;
  }
}

final venueCatalogStatusProvider = StateProvider<VenueCatalogStatus>(
  (ref) => const VenueCatalogStatus(),
);

/// Retry must invalidate the children too: rebuilding only the aggregate would
/// otherwise reuse a cached failed backend request.
final refreshVenueCatalogProvider = Provider<void Function()>((ref) => () {
      ref.invalidate(venueBackendRowsProvider);
      ref.invalidate(osmVenueCatalogProvider);
      ref.invalidate(venuesProvider);
    });

final osmVenueCatalogProvider = FutureProvider<List<Venue>>((ref) async {
  final decoded = jsonDecode(
      await rootBundle.loadString('assets/data/ulaanbaatar_osm_venues.json'));
  if (decoded is! Map<String, dynamic> ||
      decoded['kind'] != 'nightowl-osm-supplemental-venue-catalog' ||
      decoded['license'] != 'ODbL-1.0' ||
      decoded['venues'] is! List) {
    throw const FormatException('Invalid public venue catalog');
  }
  final venues = (decoded['venues'] as List).map((row) {
    if (row is! Map<String, dynamic> ||
        row['community_enabled'] != false ||
        !RegExp(r'^osm:(node|way|relation):[1-9]\d*$')
            .hasMatch(row['id']?.toString() ?? '')) {
      throw const FormatException(
          'Supplemental venue must have a public source ID');
    }
    final venue = Venue.fromJson(row);
    if (!venue.hasLocation ||
        venue.name.trim().isEmpty ||
        venue.sourceUrl == null ||
        venue.sourceLabel != 'OpenStreetMap' ||
        venue.sourceRetrievedAt == null) {
      throw const FormatException(
          'Supplemental venue provenance is incomplete');
    }
    return venue;
  }).toList();
  if (venues.length != decoded['venueCount'] ||
      venues.map((v) => v.id).toSet().length != venues.length) {
    throw const FormatException('Supplemental venue count or identity differs');
  }
  return venues;
});

String _nameKey(String name) => name.toLowerCase().replaceAll(
      RegExp(r'[^a-z0-9\u0400-\u04ff]'),
      '',
    );

double _distanceMeters(Venue a, Venue b) {
  if (!a.hasLocation || !b.hasLocation) return double.infinity;
  final lat = (b.lat! - a.lat!) * math.pi / 180;
  final lng = (b.lng! - a.lng!) * math.pi / 180;
  final value = math.pow(math.sin(lat / 2), 2) +
      math.cos(a.lat! * math.pi / 180) *
          math.cos(b.lat! * math.pi / 180) *
          math.pow(math.sin(lng / 2), 2);
  return 6371000 *
      2 *
      math.atan2(math.sqrt(value), math.sqrt(math.max(0, 1 - value)));
}

/// Backend UUIDs and owned values win. A name alone cannot identify a branch.
List<Venue> mergeVenueCatalog(List<Venue> community, List<Venue> supplement) {
  final result =
      community.where((v) => !v.isDemo && v.communityEnabled).toList();
  for (final place in supplement) {
    if (place.communityEnabled || !place.hasLocation || place.isDemo) continue;
    final index = result.indexWhere((v) =>
        v.id == place.id ||
        (v.sourceUrl != null && v.sourceUrl == place.sourceUrl) ||
        (_nameKey(v.name).isNotEmpty &&
            _nameKey(v.name) == _nameKey(place.name) &&
            _distanceMeters(v, place) <= 100));
    if (index < 0) {
      result.add(place);
    } else {
      result[index] = result[index].withSupplementalDetails(place);
    }
  }
  result.sort((a, b) {
    final name = a.name.toLowerCase().compareTo(b.name.toLowerCase());
    return name == 0 ? a.id.compareTo(b.id) : name;
  });
  return result;
}

final venuesProvider = FutureProvider<List<Venue>>((ref) async {
  var disposed = false;
  ref.onDispose(() => disposed = true);
  // Start both operations before awaiting either; errors remain explicit below.
  Future<(List<Venue>, bool)> capture(Future<List<Venue>> future) async {
    try {
      return (await future, false);
    } catch (_) {
      return (<Venue>[], true);
    }
  }

  final results = await Future.wait([
    capture(ref.watch(venueBackendRowsProvider.future)),
    capture(ref.watch(osmVenueCatalogProvider.future)),
  ]);
  final server = results[0];
  final catalog = results[1];
  final merged = mergeVenueCatalog(server.$1, catalog.$1);
  if (!disposed) {
    ref.read(venueCatalogStatusProvider.notifier).state = VenueCatalogStatus(
      communityUnavailable: server.$2,
      supplementUnavailable: catalog.$2,
      supplementalCount: merged.where((v) => !v.communityEnabled).length,
      sourceRetrievedAt:
          catalog.$1.isEmpty ? null : catalog.$1.first.sourceRetrievedAt,
    );
  }
  if (server.$2 && catalog.$2) {
    throw StateError('Community server and public venue catalog unavailable');
  }
  return merged;
});

// ─── Одоогийн хэрэглэгч venue эзэмшдэг эсэх (Discovery контент оруулах эрх) ───
final isVenueOwnerProvider = FutureProvider<bool>((ref) async {
  final me = ref.watch(sessionUserIdProvider);
  if (me == null) return false;
  try {
    final r = await SupabaseService.client
        .from('venues')
        .select('id')
        .eq('owner_id', me)
        .limit(1)
        .maybeSingle();
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
    if (venueId == null ||
        expiresAt == null ||
        !expiresAt.isAfter(DateTime.now().toUtc())) {
      state = null;
      return;
    }
    state = venueId;
    _expiry = Timer(expiresAt.difference(DateTime.now().toUtc()), () {
      if (mounted) {
        state = null;
        _loaded = false;
      }
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
        _setCurrent(r?['venue_id'] as String?,
            DateTime.tryParse(r?['expires_at']?.toString() ?? ''));
        _loaded = true;
      }
    } catch (_) {
      // чимээгүй — дараагийн check-in үед төлөв зөв болно
    }
  }

  /// null = амжилт, бусад нь хэрэглэгчид харуулах алдааны мессеж
  Future<String?> checkIn(String venueId) async {
    if (venueId.startsWith('osm:')) {
      return 'Энэ газар олон нийтийн бүртгэлд хараахан холбогдоогүй';
    }
    final user = SupabaseService.currentUser;
    if (user == null) return 'Нэвтэрнэ үү';
    if (_busy) return 'Түр хүлээнэ үү';
    _busy = true;
    ++_request;
    try {
      // Server transaction serializes per user and expires any previous venue.
      final result = await SupabaseService.client
          .rpc('check_in_venue', params: {'p_venue_id': venueId});
      final row = (result as List).single as Map;
      final expiry = DateTime.tryParse(row['expires_at']?.toString() ?? '');
      if (expiry == null || row['venue_id'] != venueId) {
        throw StateError('Invalid check-in response');
      }
      if (mounted) {
        _setCurrent(venueId, expiry);
        _loaded = true;
      }
      return null;
    } catch (_) {
      return 'Бүртгэж чадсангүй. Дахин оролдоно уу';
    } finally {
      _busy = false;
    }
  }

  /// Тухайн venue-гээс гарах (зөвхөн энэ venue-ийн мөрийг устгана)
  Future<String?> checkOut(String venueId) async {
    if (venueId.startsWith('osm:')) {
      return 'Энэ газар олон нийтийн бүртгэлд хараахан холбогдоогүй';
    }
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
    } finally {
      _busy = false;
    }
  }

  @override
  void dispose() {
    _expiry?.cancel();
    super.dispose();
  }
}

final checkInProvider = StateNotifierProvider<CheckInNotifier, String?>((ref) {
  ref.watch(sessionUserIdProvider);
  return CheckInNotifier();
});
