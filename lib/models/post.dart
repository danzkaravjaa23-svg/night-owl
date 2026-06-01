import 'user_profile.dart';
import 'venue.dart';

/// Feed post — supports both direct table query and RPC (get_feed_posts) response
class Post {
  final String id;
  final String userId;
  final String? venueId;
  final String? caption;
  final String? mediaUrl;
  final String mediaType;       // 'image' | 'video'
  final int likesCount;
  final int commentsCount;
  final bool isLikedByMe;
  final DateTime createdAt;
  final String? venueName;

  // Joined
  final UserProfile? author;
  final Venue? venue;

  const Post({
    required this.id,
    required this.userId,
    this.venueId,
    this.caption,
    this.mediaUrl,
    this.mediaType = 'image',
    this.likesCount = 0,
    this.commentsCount = 0,
    this.isLikedByMe = false,
    required this.createdAt,
    this.venueName,
    this.author,
    this.venue,
  });

  factory Post.fromJson(Map<String, dynamic> json) {
    // RPC response uses flat keys (author_username etc.)
    final isRpc = json.containsKey('author_username');

    UserProfile? author;
    if (isRpc) {
      if (json['author_id'] != null) {
        author = UserProfile(
          id:         json['author_id'] as String,
          username:   json['author_username'] as String?,
          avatarUrl:  json['author_avatar'] as String?,
          isVerified: json['author_verified'] as bool? ?? false,
        );
      }
    } else {
      author = _parseProfile(json['profiles']);
    }

    return Post(
      id:            json['id'] as String,
      userId:        (json['user_id'] ?? json['author_id']) as String,
      venueId:       json['venue_id'] as String?,
      caption:       json['caption'] as String?,
      mediaUrl:      json['media_url'] as String?,
      mediaType:     json['media_type'] as String? ?? 'image',
      likesCount:    (json['likes_count'] as num?)?.toInt() ?? 0,
      commentsCount: (json['comments_count'] as num?)?.toInt() ?? 0,
      isLikedByMe:   json['is_liked_by_me'] as bool? ?? false,
      createdAt:     DateTime.parse(json['created_at'] as String),
      venueName:     (json['venue_name'] ?? json['venues']?['name']) as String?,
      author:        author,
      venue:         isRpc ? null : _parseVenue(json['venues']),
    );
  }

  Post copyWith({
    bool? isLikedByMe,
    int? likesCount,
    int? commentsCount,
  }) => Post(
    id: id, userId: userId, venueId: venueId,
    caption: caption, mediaUrl: mediaUrl, mediaType: mediaType,
    likesCount:    likesCount    ?? this.likesCount,
    commentsCount: commentsCount ?? this.commentsCount,
    isLikedByMe:   isLikedByMe   ?? this.isLikedByMe,
    createdAt: createdAt, venueName: venueName,
    author: author, venue: venue,
  );

  static UserProfile? _parseProfile(dynamic p) {
    if (p == null) return null;
    try { return UserProfile.fromJson(p as Map<String, dynamic>); }
    catch (_) { return null; }
  }

  static Venue? _parseVenue(dynamic v) {
    try { return v != null ? Venue.fromJson(v as Map<String, dynamic>) : null; }
    catch (_) { return null; }
  }

  String get timeAgo {
    final diff = DateTime.now().difference(createdAt);
    if (diff.inSeconds < 60)  return 'Одоо';
    if (diff.inMinutes < 60)  return '${diff.inMinutes}м өмнө';
    if (diff.inHours   < 24)  return '${diff.inHours}ц өмнө';
    if (diff.inDays    < 7)   return '${diff.inDays}х өмнө';
    return '${createdAt.month}/${createdAt.day}';
  }

  String get formattedLikes =>
      likesCount >= 1000
          ? '${(likesCount / 1000).toStringAsFixed(1)}k'
          : '$likesCount';

  String get formattedComments =>
      commentsCount >= 1000
          ? '${(commentsCount / 1000).toStringAsFixed(1)}k'
          : '$commentsCount';
}
