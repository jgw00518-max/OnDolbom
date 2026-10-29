/// 서버가 현재 공간 접근 권한까지 확인한 일정 알림.
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
  });
  final String id;
  final String type;
  final String spaceId;
  final String recipientName;
  final int scheduleId;
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
  );

  String get title => switch (type) {
    'schedule_reminder' => '시작까지 72시간 이내, 돌봄 담당자가 필요해요',
    'schedule_accepted' => '가족이 돌봄 일정을 수락했어요',
    'schedule_reconfirmed' => '담당자가 변경된 일정을 재수락했어요',
    'schedule_declined' => '담당자가 재수락을 거절했어요',
    'schedule_deleted' => '돌봄 일정이 삭제되었어요',
    'schedule_changed' => '돌봄 일정이 변경되었어요',
    'schedule_reconfirm' => '변경된 일정을 다시 확인해 주세요',
    'schedule_recruitment' => '돌봄 담당자를 다시 모집해요',
    _ => '새로운 돌봄 일정이 등록되었어요',
  };

  factory ScheduleNotification.fromJson(Map<String, dynamic> json) =>
      ScheduleNotification(
        id: json['notification_id'].toString(),
        type: json['notification_type'] as String? ?? 'schedule_created',
        spaceId: json['family_room_id'] as String,
        recipientName: json['care_recipient_name'] as String,
        scheduleId: json['schedule_seq'] as int,
        scheduleName: json['schedule_name'] as String?,
        date: json['schedule_date'] as String,
        startTime: json['start_time'] as String,
        endTime: json['end_time'] as String,
        createdAt: json['created_at'] as String,
        readAt: json['read_at'] as String?,
        memo: json['schedule_memo'] as String?,
      );
}
