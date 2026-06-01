import 'venue.dart';

/// Venue event
class VenueEvent {
  final String id;
  final String venueId;
  final String title;
  final String? description;
  final DateTime date;
  final int? ticketPrice;
  final int? capacity;
  final String status; // 'draft' | 'active'
  final int goingCount;
  final bool isGoing;
  final Venue? venue;

  const VenueEvent({
    required this.id,
    required this.venueId,
    required this.title,
    this.description,
    required this.date,
    this.ticketPrice,
    this.capacity,
    this.status = 'draft',
    this.goingCount = 0,
    this.isGoing = false,
    this.venue,
  });

  bool get isToday {
    final now = DateTime.now();
    return date.year == now.year &&
        date.month == now.month &&
        date.day == now.day;
  }

  String get formattedPrice => ticketPrice == null || ticketPrice == 0
      ? 'Free'
      : '₮${_fmt(ticketPrice!)}';

  String _fmt(int n) {
    final s = n.toString();
    final buf = StringBuffer();
    for (int i = 0; i < s.length; i++) {
      if (i > 0 && (s.length - i) % 3 == 0) buf.write(',');
      buf.write(s[i]);
    }
    return buf.toString();
  }

  factory VenueEvent.fromJson(Map<String, dynamic> json) => VenueEvent(
    id:          json['id'] as String,
    venueId:     json['venue_id'] as String,
    title:       json['title'] as String,
    description: json['description'] as String?,
    date:        DateTime.parse(json['starts_at'] as String),
    ticketPrice: json['price'] as int?,
    capacity:    json['capacity'] as int?,
    status:      json['status'] as String? ?? 'active',
    goingCount:  json['attendee_count'] as int? ?? 0,
    isGoing:     json['is_going'] as bool? ?? false,
    venue:       json['venues'] != null
        ? Venue.fromJson(json['venues'] as Map<String, dynamic>)
        : null,
  );
}
