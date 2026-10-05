// Venue — pub / lounge / nightclub / restaurant / rooftop
// Optional fields remain nullable when the database has no verified value.
import 'venue_location.dart';

class Venue {
  final String id;
  final String name;
  final String type;
  final String? address;
  final String? district;
  final double? lat;
  final double? lng;
  final String? locationSourceUrl;
  final String? coverUrl;   // эзний оруулсан нүүр зураг
  final List<String> photos;
  final String? phone;
  final String? openTime;
  final String? closeTime;
  final bool verified;
  final bool isOpen;
  final int checkinCount;   // бодит цагийн check-in тоо
  final double rating;
  final Map<String, String> openingHours; // {'mon': '21:00-05:00', ...}
  final DateTime createdAt;

  const Venue({
    required this.id,
    required this.name,
    required this.type,
    this.address,
    this.district,
    this.lat,
    this.lng,
    this.locationSourceUrl,
    this.coverUrl,
    this.photos = const [],
    this.phone,
    this.openTime,
    this.closeTime,
    this.verified = false,
    this.isOpen = false,
    this.checkinCount = 0,
    this.rating = 0,
    this.openingHours = const {},
    required this.createdAt,
  });

  factory Venue.fromJson(Map<String, dynamic> json) {
    final location = VenueLocation.resolve(json['name'] as String? ?? '',
      double.tryParse(json['lat']?.toString() ?? ''),
      double.tryParse(json['lng']?.toString() ?? ''));
    return Venue(
    id:           json['id'] as String,
    name:         json['name'] as String? ?? '',
    type:         json['venue_type'] as String? ?? json['type'] as String? ?? 'venue',
    address:      json['address'] as String?,
    district:     json['district'] as String?,
    lat:          location.lat,
    lng:          location.lng,
    locationSourceUrl: location.sourceUrl,
    coverUrl:     json['cover_url'] as String?,
    photos:       List<String>.from(json['photos'] ?? []),
    phone:        json['phone'] as String?,
    openTime:     json['open_time'] as String?,
    closeTime:    json['close_time'] as String?,
    verified:     json['verified'] as bool? ?? false,
    isOpen:       json['is_open'] as bool? ?? false,
    checkinCount: (json['checkin_count'] as num?)?.toInt() ?? 0,
    rating:       (json['rating'] as num?)?.toDouble() ?? 0,
    openingHours: Map<String, String>.from(json['opening_hours'] ?? {}),
    createdAt:    DateTime.tryParse(json['created_at']?.toString() ?? '') ?? DateTime.now(),
    );
  }

  bool get hasLocation => lat != null && lng != null && lat!.isFinite && lng!.isFinite
      && lat!.abs() <= 90 && lng!.abs() <= 180 && !(lat == 0 && lng == 0);

  // These load-test rows are documented in supabase_cleanup_fake_venues.sql.
  bool get isDemo => RegExp(r' #\d+$').hasMatch(name);

  /// null means hours are unknown; do not advertise an unverified open status.
  bool? isOpenAt(DateTime now) {
    final local = now.toUtc().add(const Duration(hours: 8));
    final start = _minutes(openTime);
    final end = _minutes(closeTime);
    if (start == null || end == null) return null;
    final minute = local.hour * 60 + local.minute;
    if (start == end) return null;
    return start < end ? minute >= start && minute < end : minute >= start || minute < end;
  }

  static int? _minutes(String? time) {
    final match = RegExp(r'^(\d{1,2}):(\d{2})(?::\d{2})?$').firstMatch(time?.trim() ?? '');
    if (match == null) return null;
    final hour = int.parse(match[1]!); final minute = int.parse(match[2]!);
    return hour < 24 && minute < 60 ? hour * 60 + minute : null;
  }

  String get emoji => switch (type) {
    'bar'       => '🍸',
    'karaoke'   => '🎤',
    'jazz'      => '🎷',
    'pub'       => '🍺',
    'lounge'    => '🍸',
    'nightclub' => '🎧',
    'restaurant'=> '🍽️',
    'rooftop'   => '🌃',
    _           => '🎵',
  };

  String get typeLabel => switch (type) {
    'bar'       => 'Bar',
    'karaoke'   => 'Karaoke',
    'jazz'      => 'Jazz',
    'pub'       => 'Pub',
    'lounge'    => 'Lounge',
    'nightclub' => 'Night Club',
    'restaurant'=> 'Restaurant',
    'rooftop'   => 'Rooftop Bar',
    _           => 'Venue',
  };
}
