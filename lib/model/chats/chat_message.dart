class ChatMessage {
  const ChatMessage({
    required this.seq,
    required this.roomId,
    required this.userId,
    required this.content,
    this.clientId,
    this.sentAt,
    this.authorName,
  });
  final int seq;
  final String roomId;
  final String userId;
  final String? authorName;
  String get authorLabel =>
      authorName?.trim().isNotEmpty == true ? authorName!.trim() : '이름 없는 가족';
  final String content;
  final String? clientId;
  final DateTime? sentAt;

  factory ChatMessage.fromJson(Map<String, dynamic> json) => ChatMessage(
    seq: json['chat_seq'] as int,
    roomId: json['family_room_id'] as String,
    userId: json['user_id'] as String,
    authorName: json['author_name'] as String?,
    content: json['chat_content'] as String? ?? '',
    clientId: json['client_message_id'] as String?,
    // 서버 DATETIME에는 시간대가 없으므로 임의의 UTC 변환을 하지 않는다.
    sentAt: json['sent_at'] == null
        ? null
        : DateTime.parse(json['sent_at'] as String),
  );
}
