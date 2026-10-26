class Medication {
  const Medication({
    required this.seq,
    required this.familyRoomId,
    required this.userId,
    required this.date,
    this.info,
    this.time,
    this.dosage,
    this.unit,
    this.confirmedAt,
    this.recordedAt,
    this.updatedAt,
    this.authorName,
    this.confirmedByUserId,
    this.confirmedByName,
  });

  final int seq;
  final String familyRoomId;
  final String userId;
  final String? authorName;
  String get authorLabel =>
      authorName?.trim().isNotEmpty == true ? authorName!.trim() : '이름 없는 가족';
  final DateTime date;
  final String? info;
  final String? time;
  final String? dosage;
  final String? unit;
  final DateTime? confirmedAt;
  final String? confirmedByUserId;
  final String? confirmedByName;
  String get confirmedByLabel => confirmedByName?.trim().isNotEmpty == true
      ? confirmedByName!.trim()
      : confirmedByUserId == null
      ? '확인자 정보 없음'
      : '이름 없는 가족';
  final DateTime? recordedAt;
  final DateTime? updatedAt;

  bool get isConfirmed => confirmedAt != null;
  String get doseLabel {
    if (dosage == null) return unit ?? '';
    final value = dosage!.contains('.')
        ? dosage!
              .replaceFirst(RegExp(r'0+$'), '')
              .replaceFirst(RegExp(r'\.$'), '')
        : dosage!;
    return '$value${unit ?? ''}';
  }

  factory Medication.fromJson(Map<String, dynamic> json) => Medication(
    seq: json['medication_log_seq'] as int,
    familyRoomId: json['family_room_id'] as String,
    userId: json['user_id'] as String,
    authorName: json['author_name'] as String?,
    info: json['medication_info'] as String?,
    date: DateTime.parse(json['medication_date'] as String),
    time: json['medication_time'] as String?,
    dosage: json['dosage']?.toString(),
    unit: json['dosage_unit'] as String?,
    confirmedAt: _date(json['medication_confirmed_at']),
    confirmedByUserId: json['confirmed_by_user_id'] as String?,
    confirmedByName: json['confirmed_by_name'] as String?,
    recordedAt: _date(json['recorded_at']),
    updatedAt: _date(json['record_updated_at']),
  );

  Medication withConfirmation(
    DateTime at,
    String? checkerId,
    String? checkerName,
  ) => Medication(
    seq: seq,
    familyRoomId: familyRoomId,
    userId: userId,
    date: date,
    info: info,
    time: time,
    dosage: dosage,
    unit: unit,
    authorName: authorName,
    recordedAt: recordedAt,
    updatedAt: updatedAt,
    confirmedAt: at,
    confirmedByUserId: checkerId,
    confirmedByName: checkerName,
  );

  static DateTime? _date(dynamic value) =>
      value == null ? null : DateTime.parse(value as String);
}

String medicationDateKey(DateTime date) =>
    '${date.year.toString().padLeft(4, '0')}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';

String medicationConfirmationLabel(Medication item) {
  final at = item.confirmedAt;
  if (at == null) return '복약 전';
  final period = at.hour < 12 ? '오전' : '오후';
  final hour = at.hour % 12 == 0 ? 12 : at.hour % 12;
  final minute = at.minute.toString().padLeft(2, '0');
  return '체크: ${item.confirmedByLabel}\n체크 시간: $period $hour시 $minute분';
}

// 부동소수점 변환 없이 서버의 DECIMAL(10,3) 입력 범위를 검사한다.
bool isValidMedicationDosage(String input) {
  final value = input.trim();
  if (!RegExp(r'^\d{1,7}(\.\d{1,3})?$').hasMatch(value)) return false;
  return RegExp(r'[1-9]').hasMatch(value);
}
