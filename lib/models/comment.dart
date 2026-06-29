import 'user_profile.dart';

class Comment {
  final String id;
  final String postId;
  final String userId;
  final String body;
  final String? parentId;       // reply бол эх сэтгэгдлийн id
  final int likesCount;
  final bool isLikedByMe;
  final DateTime createdAt;
  final UserProfile? author;

  const Comment({
    required this.id,
    required this.postId,
    required this.userId,
    required this.body,
    this.parentId,
    this.likesCount = 0,
    this.isLikedByMe = false,
    required this.createdAt,
    this.author,
  });

  factory Comment.fromJson(Map<String, dynamic> json) => Comment(
    id:           json['id'] as String,
    postId:       json['post_id'] as String,
    userId:       json['user_id'] as String,
    body:         json['body'] as String,
    parentId:     json['parent_id'] as String?,
    likesCount:   (json['likes_count'] as num?)?.toInt() ?? 0,
    isLikedByMe:  json['is_liked_by_me'] as bool? ?? false,
    createdAt:    DateTime.tryParse(json['created_at']?.toString() ?? '') ?? DateTime.now(),
    author:       _parseProfile(json['profiles']),
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
