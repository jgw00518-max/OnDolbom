class Memo {
  final String memoId;
  final String familyRoomId;
  final String userId;
  final String? memoContent;
  final int? likes;
  final DateTime? writtenAt;
  final DateTime? memoUpdatedAt;

  const Memo(
    {
      required this.memoId,
      required this.familyRoomId,
      required this.userId,
      this.memoContent,
      this.likes,
      this.writtenAt,
      this.memoUpdatedAt
    }
  );

  // 서버 JSON → Dart 객체
  factory Memo.fromJson(Map<String, dynamic> json) {
    return Memo(
      memoId: json['memo_id'] as String,
      familyRoomId: json['family_room_id'] as String,
      userId: json['user_id'] as String,
      memoContent: json['memo_content'] as String?,
      likes: json['likes'] as int?,
      writtenAt: json['written_at'] == null
        ? null
        : DateTime.parse(json['written_at'] as String),
      memoUpdatedAt: json['memo_updated_at'] == null
        ? null
        : DateTime.parse(json['memo_updated_at'] as String)
    );
  }

  // Dart 객체 → JSON
  Map<String, dynamic> toJson() {
    return {
      'memo_id': memoId,
      'family_room_id': familyRoomId,
      'user_id': userId,
      'memo_content': memoContent,
      'likes': likes,
      'written_at': writtenAt?.toIso8601String(),
      'memo_updated_at': memoUpdatedAt?.toIso8601String(),
    };
  }
}
