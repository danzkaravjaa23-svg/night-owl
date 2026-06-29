import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/services/supabase_service.dart';
import '../../../models/message.dart';

// ─── Thread messages — realtime ───
final threadMessagesProvider =
    StreamProvider.family<List<Message>, String>((ref, peerId) {
  final me = SupabaseService.currentUser?.id;
  if (me == null) return const Stream.empty();

  // conversation_id-р scope — бүх messages хүснэгтийг sub хийхгүй
  final cid = ([me, peerId]..sort()).join('_');

  return SupabaseService.client
      .from('messages')
      .stream(primaryKey: ['id'])
      .eq('conversation_id', cid)
      .order('created_at')
      .map((rows) => rows.map((r) => Message.fromJson(r)).toList());
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
