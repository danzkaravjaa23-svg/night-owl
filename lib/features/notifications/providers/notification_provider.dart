import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/services/supabase_service.dart';

class AppNotification {
  final String id;
  final String type;  // 'like' | 'follow' | 'comment' | 'event'
  final String actorId;
  final String? actorName;
  final String? actorAvatar;
  final String message;
  final bool isRead;
  final DateTime createdAt;

  const AppNotification({
    required this.id,
    required this.type,
    required this.actorId,
    this.actorName,
    this.actorAvatar,
    required this.message,
    this.isRead = false,
    required this.createdAt,
  });

  factory AppNotification.fromJson(Map<String, dynamic> json) =>
      AppNotification(
        id:          json['id'] as String,
        type:        json['type'] as String,
        actorId:     json['actor_id'] as String,
        actorName:   json['actor_name'] as String?,
        actorAvatar: json['actor_avatar'] as String?,
        message:     json['message'] as String,
        isRead:      json['is_read'] as bool? ?? false,
        createdAt:   DateTime.parse(json['created_at'] as String),
      );
}

// ─── Notifications stream ───
final notificationsProvider =
    StreamProvider<List<AppNotification>>((ref) {
  final me = SupabaseService.currentUser?.id;
  if (me == null) return const Stream.empty();

  return SupabaseService.client
      .from('notifications')
      .stream(primaryKey: ['id'])
      .eq('user_id', me)
      .order('created_at', ascending: false)
      .limit(50)
      .map((rows) => rows
          .map((r) => AppNotification.fromJson(r as Map<String, dynamic>))
          .toList());
});

// ─── Unread count ───
final unreadNotifCountProvider = Provider<int>((ref) {
  final notifs = ref.watch(notificationsProvider);
  return notifs.value?.where((n) => !n.isRead).length ?? 0;
});

// ─── Mark all as read ───
Future<void> markAllNotifsRead() async {
  final me = SupabaseService.currentUser?.id;
  if (me == null) return;
  await SupabaseService.client
      .from('notifications')
      .update({'is_read': true})
      .eq('user_id', me)
      .eq('is_read', false);
}

// ─── FCM setup (Firebase хожим нэмэх үед идэвхжүүлнэ) ───
Future<void> setupPushNotifications() async {
  // TODO: Firebase тохиргоо хийсний дараа энд FCM код нэмнэ
}

Future<void> _saveToken(String token) async {
  final me = SupabaseService.currentUser?.id;
  if (me == null) return;
  await SupabaseService.client.from('profiles').update({
    'fcm_token': token,
  }).eq('id', me);
}
