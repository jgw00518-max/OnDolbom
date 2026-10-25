// 서버에서 조회한 가족 초대 정보
class FamilyInvite {
  const FamilyInvite({
    required this.inviteId,
    required this.familyRoomId,
    required this.inviteEmail,
    required this.inviteAt,
    required this.inviteStatus,
    required this.recipientName,
    this.inviterName,
  });

  final String inviteId;
  final String familyRoomId;
  final String inviteEmail;
  final DateTime inviteAt;
  final String inviteStatus;
  final String recipientName;
  final String? inviterName;

  // 받은 초대 API 응답을 객체로 변환한다.
  factory FamilyInvite.fromJson(Map<String, dynamic> json) {
    return FamilyInvite(
      inviteId: json['invite_id'] as String,
      familyRoomId: json['family_room_id'] as String,
      inviteEmail: json['invite_email'] as String,
      inviteAt: DateTime.parse(json['invite_at'] as String),
      inviteStatus: json['invite_status'] as String,
      recipientName: json['care_recipient_name'] as String,
      inviterName: json['inviter_name'] as String?,
    );
  }
}