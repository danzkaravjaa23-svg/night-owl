import 'user_profile.dart';

/// DM thread message
class Message {
  final String id;
  final String senderId;
  final String receiverId;
  final String content;
  final bool isRead;
  final DateTime createdAt;
  final UserProfile? sender;

  const Message({
    required this.id,
    required this.senderId,
    required this.receiverId,
    required this.content,
    this.isRead = false,
    required this.createdAt,
    this.sender,
  });

  factory Message.fromJson(Map<String, dynamic> json) => Message(
    id:         json['id'] as String,
    senderId:   json['sender_id'] as String,
    receiverId: json['receiver_id'] as String,
    content:    json['body'] as String? ?? '',
    isRead:     json['is_read'] as bool? ?? false,
    createdAt:  DateTime.parse(json['created_at'] as String),
    sender:     json['sender'] != null
        ? UserProfile.fromJson(json['sender'] as Map<String, dynamic>)
        : null,
  );
}

/// Chat thread summary (DM list-д харагдах)
class ChatThread {
  final String peerId;
  final UserProfile? peer;
  final String lastMessage;
  final DateTime lastAt;
  final int unreadCount;
  final bool peerOnline;

  const ChatThread({
    required this.peerId,
    this.peer,
    required this.lastMessage,
    required this.lastAt,
    this.unreadCount = 0,
    this.peerOnline = false,
  });

  factory ChatThread.fromJson(Map<String, dynamic> json) => ChatThread(
    peerId:      json['peer_id'] as String,
    peer:        json['peer'] != null
        ? UserProfile.fromJson(json['peer'] as Map<String, dynamic>)
        : null,
    lastMessage: json['last_message'] as String? ?? '',
    lastAt:      DateTime.parse(json['last_at'] as String),
    unreadCount: json['unread_count'] as int? ?? 0,
    peerOnline:  json['peer_online'] as bool? ?? false,
  );
}
