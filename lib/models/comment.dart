import 'user_profile.dart';

class Comment {
  final String id;
  final String postId;
  final String userId;
  final String body;
  final int likesCount;
  final DateTime createdAt;
  final UserProfile? author;

  const Comment({
    required this.id,
    required this.postId,
    required this.userId,
    required this.body,
    this.likesCount = 0,
    required this.createdAt,
    this.author,
  });

  factory Comment.fromJson(Map<String, dynamic> json) => Comment(
    id:         json['id'] as String,
    postId:     json['post_id'] as String,
    userId:     json['user_id'] as String,
    body:       json['body'] as String,
    likesCount: json['likes_count'] as int? ?? 0,
    createdAt:  DateTime.parse(json['created_at'] as String),
    author:     _parseProfile(json['profiles']),
  );

  static UserProfile? _parseProfile(dynamic p) {
    if (p == null) return null;
    try { return UserProfile.fromJson(p as Map<String, dynamic>); }
    catch (_) { return null; }
  }

  String get timeAgo {
    final diff = DateTime.now().difference(createdAt);
    if (diff.inSeconds < 60) return 'Одоо';
    if (diff.inMinutes < 60) return '${diff.inMinutes}м';
    if (diff.inHours   < 24) return '${diff.inHours}ц';
    return '${diff.inDays}х';
  }
}
