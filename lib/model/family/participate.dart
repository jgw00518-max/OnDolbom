// 누가 어떤 가족공간에 참여하고, 주보호자인지

class Participate {
  final int participateSeq;
  final String userId;
  final String familyRoomId;
  final bool isRepresentative;
  final DateTime joinedAt;
  final DateTime? leftAt;

  const Participate({
    required this.participateSeq,
    required this.userId,
    required this.familyRoomId,
    required this.isRepresentative,
    required this.joinedAt,
    this.leftAt,
  });

  // 서버에서 받은 참여 정보를 객체로 변환한다.
  factory Participate.fromJson(Map<String, dynamic> json) {
    return Participate(
      participateSeq: (json['participate_seq'] as num).toInt(),
      userId: json['user_id'] as String,
      familyRoomId: json['family_room_id'] as String,
      isRepresentative: json['is_representative'] == 1,
      joinedAt: DateTime.parse(json['joined_at'] as String),
      leftAt: json['left_at'] == null
          ? null
          : DateTime.parse(json['left_at'] as String),
    );
  }

  // DB의 참여 종료 여부와 같은 기준으로 판단한다.
  bool get isActive => leftAt == null;
}