/// 서버가 현재 공간 접근 권한까지 확인한 일정 등록 알림.
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
  });
  final int id;
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

  factory ScheduleNotification.fromJson(Map<String, dynamic> json) =>
      ScheduleNotification(
        id: json['notification_id'] as int,
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
