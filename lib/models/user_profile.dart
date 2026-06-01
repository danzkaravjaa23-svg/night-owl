/// Хэрэглэгчийн профайл
class UserProfile {
  final String id;
  final String? username;
  final String? name;
  final String? bio;
  final String? avatarUrl;
  final List<String> interests;
  final bool isVerified;
  final bool isBusiness;
  final int followersCount;
  final int followingCount;
  final int postsCount;
  final DateTime createdAt;

  UserProfile({
    required this.id,
    this.username,
    this.name,
    this.bio,
    this.avatarUrl,
    this.interests      = const [],
    this.isVerified     = false,
    this.isBusiness     = false,
    this.followersCount = 0,
    this.followingCount = 0,
    this.postsCount     = 0,
    DateTime? createdAt,
  }) : createdAt = createdAt ?? DateTime(2024);

  factory UserProfile.fromJson(Map<String, dynamic> json) => UserProfile(
    id:             json['id'] as String,
    username:       json['username'] as String?,
    name:           (json['full_name'] ?? json['name']) as String?,
    bio:            json['bio'] as String?,
    avatarUrl:      json['avatar_url'] as String?,
    interests:      List<String>.from(json['interests'] ?? []),
    isVerified:     json['is_verified'] as bool? ?? false,
    isBusiness:     json['is_business'] as bool? ?? false,
    followersCount: json['followers_count'] as int? ?? 0,
    followingCount: json['following_count'] as int? ?? 0,
    postsCount:     json['posts_count'] as int? ?? 0,
    createdAt:      json['created_at'] != null
        ? DateTime.parse(json['created_at'] as String)
        : null,
  );

  Map<String, dynamic> toJson() => {
    'id':          id,
    'username':    username,
    'full_name':   name,
    'bio':         bio,
    'avatar_url':  avatarUrl,
    'interests':   interests,
    'is_business': isBusiness,
    'updated_at':  DateTime.now().toIso8601String(),
  };

  UserProfile copyWith({
    String? username, String? name, String? bio,
    String? avatarUrl, List<String>? interests,
    bool? isVerified, bool? isBusiness,
    int? followersCount, int? followingCount, int? postsCount,
  }) => UserProfile(
    id:             id,
    username:       username       ?? this.username,
    name:           name           ?? this.name,
    bio:            bio            ?? this.bio,
    avatarUrl:      avatarUrl      ?? this.avatarUrl,
    interests:      interests      ?? this.interests,
    isVerified:     isVerified     ?? this.isVerified,
    isBusiness:     isBusiness     ?? this.isBusiness,
    followersCount: followersCount ?? this.followersCount,
    followingCount: followingCount ?? this.followingCount,
    postsCount:     postsCount     ?? this.postsCount,
    createdAt:      createdAt,
  );

  /// Avatar initial letter
  String get initial => (name?.isNotEmpty == true
      ? name![0]
      : username?.replaceAll('@', '')[0] ?? '?').toUpperCase();
}
