/// Хэрэглэгчийн профайл
class UserProfile {
  final String id;
  final String? username;
  final String? name;
  final String? bio;
  final String? avatarUrl;
  final String? coverUrl;
  final List<String> interests;
  final bool isVerified;
  final bool isBusiness;
  final bool isAdmin;
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
    this.coverUrl,
    this.interests      = const [],
    this.isVerified     = false,
    this.isBusiness     = false,
    this.isAdmin        = false,
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
    coverUrl:       json['cover_url'] as String?,
    interests:      List<String>.from(json['interests'] ?? []),
    isVerified:     json['is_verified'] as bool? ?? false,
    isBusiness:     json['is_business'] as bool? ?? false,
    isAdmin:        json['is_admin'] as bool? ?? false,
    followersCount: (json['followers_count'] as num?)?.toInt() ?? 0,
    followingCount: (json['following_count'] as num?)?.toInt() ?? 0,
    postsCount:     (json['posts_count'] as num?)?.toInt() ?? 0,
    createdAt:      DateTime.tryParse(json['created_at']?.toString() ?? ''),
  );

  Map<String, dynamic> toJson() => {
    'id':          id,
    'username':    username,
    'full_name':   name,
    'bio':         bio,
    'avatar_url':  avatarUrl,
    'cover_url':   coverUrl,
    'interests':   interests,
    'is_business': isBusiness,
    'updated_at':  DateTime.now().toIso8601String(),
  };

  UserProfile copyWith({
    String? username, String? name, String? bio,
    String? avatarUrl, String? coverUrl, List<String>? interests,
    bool? isVerified, bool? isBusiness, bool? isAdmin,
    int? followersCount, int? followingCount, int? postsCount,
  }) => UserProfile(
    id:             id,
    username:       username       ?? this.username,
    name:           name           ?? this.name,
    bio:            bio            ?? this.bio,
    avatarUrl:      avatarUrl      ?? this.avatarUrl,
    coverUrl:       coverUrl       ?? this.coverUrl,
    interests:      interests      ?? this.interests,
    isVerified:     isVerified     ?? this.isVerified,
    isBusiness:     isBusiness     ?? this.isBusiness,
    isAdmin:        isAdmin        ?? this.isAdmin,
    followersCount: followersCount ?? this.followersCount,
    followingCount: followingCount ?? this.followingCount,
    postsCount:     postsCount     ?? this.postsCount,
    createdAt:      createdAt,
  );

  /// Avatar initial letter (хоосон тэмдэгт дээр RangeError гаргахгүй)
  String get initial {
    final n = name?.trim() ?? '';
    if (n.isNotEmpty) return n[0].toUpperCase();
    final u = (username ?? '').replaceAll('@', '').trim();
    return (u.isNotEmpty ? u[0] : '?').toUpperCase();
  }
}
