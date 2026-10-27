class ChatMessage {
  const ChatMessage({
    required this.seq,
    required this.roomId,
    required this.userId,
    required this.content,
    this.clientId,
    this.sentAt,
    this.authorName,
    this.hasImage = false,
    this.updatedAt,
    this.deletedAt,
    this.isDeleted = false,
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
  final bool hasImage;
  final DateTime? updatedAt;
  final DateTime? deletedAt;
  final bool isDeleted;

  factory ChatMessage.fromJson(Map<String, dynamic> json) => ChatMessage(
    seq: json['chat_seq'] as int,
    roomId: json['family_room_id'] as String,
    userId: json['user_id'] as String,
    authorName: json['author_name'] as String?,
    content:
        json['is_deleted'] == true ||
            json['is_deleted'] == 1 ||
            json['live_chat_deleted_at'] != null
        ? '삭제된 메시지입니다.'
        : json['chat_content'] as String? ?? '',
    clientId: json['client_message_id'] as String?,
    hasImage:
        json['live_chat_deleted_at'] == null &&
        json['is_deleted'] != true &&
        json['is_deleted'] != 1 &&
        (json['has_image'] == true || json['has_image'] == 1),
    isDeleted:
        json['is_deleted'] == true ||
        json['is_deleted'] == 1 ||
        json['live_chat_deleted_at'] != null,
    updatedAt: json['live_chat_updated_at'] == null
        ? null
        : DateTime.parse(json['live_chat_updated_at'] as String),
    deletedAt: json['live_chat_deleted_at'] == null
        ? null
        : DateTime.parse(json['live_chat_deleted_at'] as String),
    // 서버 DATETIME에는 시간대가 없으므로 임의의 UTC 변환을 하지 않는다.
    sentAt: json['sent_at'] == null
        ? null
        : DateTime.parse(json['sent_at'] as String),
  );
}
