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
    this.expiresAt,
    this.canResend = false,
  });

  final String inviteId;
  final String familyRoomId;
  final String inviteEmail;
  final DateTime inviteAt;
  final String inviteStatus;
  final String recipientName;
  final String? inviterName;
  final DateTime? expiresAt;
  // 재요청 권한은 기기 판단 대신 서버가 원래 발신자·현재 역할로 결정한다.
  final bool canResend;

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
      expiresAt: DateTime.tryParse(json['expires_at']?.toString() ?? ''),
      canResend: json['can_resend'] == true || json['can_resend'] == 1,
    );
  }
}
