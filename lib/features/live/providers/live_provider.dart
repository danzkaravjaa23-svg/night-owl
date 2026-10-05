import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Идэвхтэй live-ийн нэг мөр
class LiveItem {
  final String id;
  final String userId;
  final String title;
  final int viewers;
  final String username;
  final String? avatarUrl;
  final String? venueName;
  const LiveItem({
    required this.id,
    required this.userId,
    required this.title,
    required this.viewers,
    required this.username,
    this.avatarUrl,
    this.venueName,
  });

  /// Газрын нэр байвал түүгээр, эс бол хэрэглэгчийн нэрээр
  String get displayName => (venueName != null && venueName!.isNotEmpty)
      ? venueName! : username;
}

/// Идэвхтэй (is_live=true) live-ууд — discovery rail-д харагдана
final activeLivesProvider = FutureProvider<List<LiveItem>>((ref) async {
  // No media transport exists yet. Local recording rows are not live streams.
  return const [];
});
