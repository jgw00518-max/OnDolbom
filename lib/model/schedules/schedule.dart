// 월별 조회와 일정 상세 화면에서 사용하는 일정 정보
class Schedule {
  const Schedule({
    required this.seq,
    required this.date,
    required this.startTime,
    required this.endTime,
    required this.state,
    this.name,
    this.memo,
    this.creatorName,
    this.acceptedBy,
    this.acceptedName,
  });

  final int seq;
  final DateTime date;
  final String startTime;
  final String endTime;
  final String state;
  final String? name;
  final String? memo;
  final String? creatorName;
  final String? acceptedBy;
  final String? acceptedName;

  String get title => name == null || name!.trim().isEmpty ? '돌봄 일정' : name!;
  String get assignment => acceptedBy == null ? '담당자 모집 중' : '담당자 등록 완료';

  factory Schedule.fromJson(Map<String, dynamic> json) {
    return Schedule(
      seq: (json['schedule_seq'] as num).toInt(),
      date: DateTime.parse(json['schedule_date'] as String),
      startTime: (json['start_time'] as String).substring(0, 5),
      endTime: (json['end_time'] as String).substring(0, 5),
      state: json['schedule_state'] as String,
      name: json['schedule_name'] as String?,
      memo: json['schedule_memo'] as String?,
      creatorName: json['creator_name'] as String?,
      acceptedBy: json['accepted_by'] as String?,
      acceptedName: json['accepted_name'] as String?,
    );
  }
}
