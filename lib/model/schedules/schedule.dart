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
    this.historySeq,
    this.reconfirmRequired = false,
    this.reconfirmUserId,
    this.previousSchedule,
    this.reconfirmResponseDueAt,
    this.reconfirmIsUrgent = false,
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

  // 최신 변경 이력 번호
  final int? historySeq;

  // 기존 담당자의 재수락을 기다리는지 여부
  final bool reconfirmRequired;

  // 재수락 요청을 받은 가족의 사용자 ID
  final String? reconfirmUserId;

  // 재수락 요청 직전의 일정 내용
  final PreviousSchedule? previousSchedule;

    // 일반 재수락 요청의 응답 기한
  final DateTime? reconfirmResponseDueAt;

  // 요청 당시 시작까지 12시간 이하였는지 여부
  final bool reconfirmIsUrgent;

  String get title => name == null || name!.trim().isEmpty ? '돌봄 일정' : name!;

  String get assignment {
    if (reconfirmRequired) return '재수락 요청 중';
    return acceptedBy == null ? '담당자 모집 중' : '담당자 등록 완료';
  }

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
      historySeq: (json['history_seq'] as num?)?.toInt(),
      reconfirmRequired:
          json['reconfirm_required'] == 1 || json['reconfirm_required'] == true,
      reconfirmUserId: json['reconfirm_user_id'] as String?,
            reconfirmResponseDueAt: json['reconfirm_response_due_at'] == null
          ? null
          : DateTime.parse(json['reconfirm_response_due_at'] as String),
      reconfirmIsUrgent: json['reconfirm_is_urgent'] == true,
      previousSchedule: json['previous_schedule'] == null
          ? null
          : PreviousSchedule.fromJson(
              json['previous_schedule'] as Map<String, dynamic>,
            ),
    );
  }
}

  // 변경 전·후 비교에 사용할 이전 일정 내용
  class PreviousSchedule {
  const PreviousSchedule({
    required this.date,
    required this.startTime,
    required this.endTime,
    this.name,
    this.memo,
  });

  final DateTime date;
  final String startTime;
  final String endTime;
  final String? name;
  final String? memo;

  String get title =>
      name == null || name!.trim().isEmpty ? '돌봄 일정' : name!;

  factory PreviousSchedule.fromJson(Map<String, dynamic> json) {
    return PreviousSchedule(
      date: DateTime.parse(json['schedule_date'] as String),
      startTime: (json['start_time'] as String).substring(0, 5),
      endTime: (json['end_time'] as String).substring(0, 5),
      name: json['schedule_name'] as String?,
      memo: json['schedule_memo'] as String?,
    );
  }
}
