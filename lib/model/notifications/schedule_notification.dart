/// 일정 알림과 서버가 삭제 당시 수신 권한을 확인한 공간 삭제 안내.
class ScheduleNotification {
  const ScheduleNotification({
    required this.id,
    required this.spaceId,
    required this.recipientName,
    required this.scheduleId,
    required this.scheduleName,
    required this.date,
    required this.startTime,
    required this.endTime,
    required this.createdAt,
    required this.readAt,
    this.memo,
    this.type = 'schedule_created',
    this.roomDeletedAt,
  });
  final String id;
  final String type;
  final String spaceId;
  final String recipientName;
  final int? scheduleId;
  final String? roomDeletedAt;
  bool get isRoomDeletion => type == 'family_room_deleted';
  final String? scheduleName;
  final String date;
  final String startTime;
  final String endTime;
  final String createdAt;
  final String? readAt;
  final String? memo;

  ScheduleNotification withReadAt(String? value) => ScheduleNotification(
    id: id,
    type: type,
    spaceId: spaceId,
    recipientName: recipientName,
    scheduleId: scheduleId,
    scheduleName: scheduleName,
    date: date,
    startTime: startTime,
    endTime: endTime,
    createdAt: createdAt,
    readAt: value,
    memo: memo,
    roomDeletedAt: roomDeletedAt,
  );

  bool get isSpaceEvent => const {
    'representative_transferred',
    'member_left',
    'member_removed',
    'memo_created',
    'medication_created',
  }.contains(type);

  String get title => switch (type) {
    'representative_transferred' => '주보호자가 변경되었어요',
    'member_left' => '가족이 돌봄 공간에서 나갔어요',
    'member_removed' => '가족의 돌봄 공간 참여가 종료되었어요',
    'memo_created' => '새 메모가 등록되었어요',
    'medication_created' => '새 투약일지가 등록되었어요',
    'family_room_deleted' => '참여하던 돌봄 공간이 삭제되었어요',
    'schedule_reminder' => '시작까지 72시간 이내, 돌봄 담당자가 필요해요',
    'schedule_accepted' => '가족이 돌봄 일정을 수락했어요',
    'schedule_reconfirmed' => '담당자가 변경된 일정을 재수락했어요',
    'schedule_reconfirm_expired' => '재수락 기한이 지나 담당 배정이 해제됐어요',
    'schedule_reconfirm_unanswered' => '담당 가족이 재수락 요청에 응답하지 않았어요',
    'schedule_reconfirm_unverified' => '긴급 변경 일정의 재수락을 확인해 주세요',
    'schedule_withdrawn' => '담당 가족이 일정 참여를 취소했어요',
    'schedule_declined' => '담당자가 재수락을 거절했어요',
    'schedule_deleted' => '돌봄 일정이 삭제되었어요',
    'schedule_changed' => '돌봄 일정이 변경되었어요',
    'schedule_reconfirm' => '변경된 일정을 다시 확인해 주세요',
    'schedule_recruitment' => '돌봄 담당자를 다시 모집해요',
    _ => '새로운 돌봄 일정이 등록되었어요',
  };

  factory ScheduleNotification.fromJson(Map<String, dynamic> json) {
    final roomDeletion = json['notification_type'] == 'family_room_deleted';
    return ScheduleNotification(
      id: json['notification_id'].toString(),
      type: json['notification_type'] as String? ?? 'schedule_created',
      spaceId: json['family_room_id'] as String,
      recipientName: json['care_recipient_name'] as String,
      scheduleId: roomDeletion ? null : json['schedule_seq'] as int,
      roomDeletedAt: json['room_deleted_at'] as String?,
      scheduleName: json['schedule_name'] as String?,
      date: roomDeletion ? '' : json['schedule_date'] as String,
      startTime: roomDeletion ? '' : json['start_time'] as String,
      endTime: roomDeletion ? '' : json['end_time'] as String,
      createdAt: json['created_at'] as String,
      readAt: json['read_at'] as String?,
      memo: json['schedule_memo'] as String?,
    );
  }
}
