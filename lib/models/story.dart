import 'user_profile.dart';

class Story {
  final String id;
  final String userId;
  final String mediaUrl;
  final String mediaType;   // 'image' | 'video'
  final String? caption;
  final int duration;       // seconds per story
  final int viewCount;
  final DateTime expiresAt;
  final DateTime createdAt;
  final UserProfile? author;
  final String? venueId;
  final String? venueName;
  final List<String> mentions;
  final String? musicUrl;
  final String? musicTitle;
  final String? musicArtist;

  const Story({
    required this.id,
    required this.userId,
    required this.mediaUrl,
    this.mediaType = 'image',
    this.caption,
    this.duration = 5,
    this.viewCount = 0,
    required this.expiresAt,
    required this.createdAt,
    this.author,
    this.venueId,
    this.venueName,
    this.mentions = const [],
    this.musicUrl,
    this.musicTitle,
    this.musicArtist,
  });

  bool get isExpired => DateTime.now().isAfter(expiresAt);

  factory Story.fromJson(Map<String, dynamic> json) => Story(
    id:        json['id'] as String,
    userId:    json['user_id'] as String,
    mediaUrl:  json['media_url'] as String,
    mediaType: json['media_type'] as String? ?? 'image',
    caption:   json['caption'] as String?,
    duration:  (json['duration'] as num?)?.toInt() ?? 5,
    viewCount: (json['view_count'] as num?)?.toInt() ?? 0,
    expiresAt: DateTime.tryParse(json['expires_at']?.toString() ?? '')
        ?? DateTime.now().add(const Duration(hours: 24)),
    createdAt: DateTime.tryParse(json['created_at']?.toString() ?? '') ?? DateTime.now(),
    author:    _parseProfile(json['profiles']),
    venueId:   json['venue_id'] as String?,
    venueName: (json['venues'] as Map?)?['name'] as String?,
    mentions:  (json['mentions'] as List?)?.map((e) => e.toString()).toList()
                 ?? const [],
    musicUrl:    json['music_url'] as String?,
    musicTitle:  json['music_title'] as String?,
    musicArtist: json['music_artist'] as String?,
  );

  static UserProfile? _parseProfile(dynamic p) {
    if (p == null) return null;
    try { return UserProfile.fromJson(p as Map<String, dynamic>); }
    catch (_) { return null; }
  }
}

/// A user's story ring (grouped stories for the bar)
class StoryRing {
  final String userId;
  final UserProfile author;
  final List<Story> stories;
  final bool hasUnseenStories;

  const StoryRing({
    required this.userId,
    required this.author,
    required this.stories,
    this.hasUnseenStories = true,
  });

  Story get latest => stories.last;
}
