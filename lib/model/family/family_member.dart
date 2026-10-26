// 현재 가족 공간에 참여 중인 가족 정보
class FamilyMember {
  const FamilyMember({
    required this.participateSeq,
    required this.userId,
    required this.isRepresentative,
    required this.joinedAt,
    this.name,
    this.email,
  });

  final int participateSeq;
  final String userId;
  final bool isRepresentative;
  final DateTime joinedAt;
  final String? name;
  final String? email;

  // 서버의 가족 목록 응답을 객체로 변환한다.
  factory FamilyMember.fromJson(Map<String, dynamic> json) {
    return FamilyMember(
      participateSeq: json['participate_seq'] as int,
      userId: json['user_id'] as String,
      isRepresentative: json['is_representative'] == 1,
      joinedAt: DateTime.parse(json['joined_at'] as String),
      name: json['name'] as String?,
      email: json['user_email'] as String?,
    );
  }

  // 화면에 표시할 공간별 역할
  String get roleName {
    return isRepresentative ? '주보호자' : '일반 가족';
  }
}