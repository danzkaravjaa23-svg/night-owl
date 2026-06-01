import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/services/supabase_service.dart';
import '../../../core/constants/app_constants.dart';
import '../../../models/message.dart';

// ─── Thread messages — realtime ───
final threadMessagesProvider =
    StreamProvider.family<List<Message>, String>((ref, peerId) {
  final me = SupabaseService.currentUser?.id;
  if (me == null) return const Stream.empty();

  return SupabaseService.client
      .from('messages')
      .stream(primaryKey: ['id'])
      .order('created_at')
      .map((rows) => rows
          .where((r) =>
              (r['sender_id'] == me && r['receiver_id'] == peerId) ||
              (r['sender_id'] == peerId && r['receiver_id'] == me))
          .map((r) => Message.fromJson(r as Map<String, dynamic>))
          .toList());
});

// ─── Send message ───
Future<void> sendMessage(String receiverId, String content) async {
  final me = SupabaseService.currentUser?.id;
  if (me == null) return;
  await SupabaseService.client.from('messages').insert({
    'sender_id':   me,
    'receiver_id': receiverId,
    'body':        content,
  });
}

// ─── Mark messages as read ───
Future<void> markRead(String senderId) async {
  final me = SupabaseService.currentUser?.id;
  if (me == null) return;
  await SupabaseService.client
      .from('messages')
      .update({'is_read': true})
      .eq('sender_id', senderId)
      .eq('receiver_id', me)
      .eq('is_read', false);
}
