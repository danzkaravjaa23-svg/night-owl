/// Venue — pub / lounge / nightclub / restaurant / rooftop
/// АНХААР: address / photos / verified / is_open / opening_hours багана
/// одоогийн live DB-д БАЙХГҮЙ (42703) — fromJson default утга өгдөг тул
/// эдгээр талбар үргэлж хоосон/false байна. Migration хийсний дараа идэвхжинэ.
class Venue {
  final String id;
  final String name;
  final String type;
  final String? address;
  final String? district;
  final double? lat;
  final double? lng;
  final String? coverUrl;   // эзний оруулсан нүүр зураг
  final List<String> photos;
  final String? phone;
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
    this.coverUrl,
    this.photos = const [],
    this.phone,
    this.verified = false,
    this.isOpen = false,
    this.checkinCount = 0,
    this.rating = 0,
    this.openingHours = const {},
    required this.createdAt,
  });

  factory Venue.fromJson(Map<String, dynamic> json) => Venue(
    id:           json['id'] as String,
    name:         json['name'] as String? ?? '',
    type:         json['venue_type'] as String? ?? json['type'] as String? ?? 'venue',
    address:      json['address'] as String?,
    district:     json['district'] as String?,
    lat:          (json['lat'] as num?)?.toDouble(),
    lng:          (json['lng'] as num?)?.toDouble(),
    coverUrl:     json['cover_url'] as String?,
    photos:       List<String>.from(json['photos'] ?? []),
    phone:        json['phone'] as String?,
    verified:     json['verified'] as bool? ?? false,
    isOpen:       json['is_open'] as bool? ?? false,
    checkinCount: (json['checkin_count'] as num?)?.toInt() ?? 0,
    rating:       (json['rating'] as num?)?.toDouble() ?? 0,
    openingHours: Map<String, String>.from(json['opening_hours'] ?? {}),
    createdAt:    DateTime.tryParse(json['created_at']?.toString() ?? '') ?? DateTime.now(),
  );

  String get emoji => switch (type) {
    'pub'       => '🍺',
    'lounge'    => '🍸',
    'nightclub' => '🎧',
    'restaurant'=> '🍽️',
    'rooftop'   => '🌃',
    _           => '🎵',
  };

  String get typeLabel => switch (type) {
    'pub'       => 'Pub',
    'lounge'    => 'Lounge',
    'nightclub' => 'Night Club',
    'restaurant'=> 'Restaurant',
    'rooftop'   => 'Rooftop Bar',
    _           => 'Venue',
  };
}
