// 어떤 공간인지, 대상자가 누구인지 

class FamilyRoom {
  // 돌봄 공간 정보
  final String familyRoomId;
  final String createdBy;
  final DateTime? createdAt;
  final DateTime? familyRoomDeletedAt;

  // 해당 공간의 돌봄대상자 정보
  final String careRecipientName;
  final int? gender;
  final DateTime? birthDate;
  final String? careAddress;
  final double? latitude;
  final double? longitude;
  final String? specialNotes;

  const FamilyRoom({
    required this.familyRoomId,
    required this.createdBy,
    required this.careRecipientName,
    this.createdAt,
    this.familyRoomDeletedAt,
    this.gender,
    this.birthDate,
    this.careAddress,
    this.latitude,
    this.longitude,
    this.specialNotes,
  });

  // 서버에서 받은 JSON을 FamilyRoom 객체로 변환한다.
  factory FamilyRoom.fromJson(Map<String, dynamic> json) {
    return FamilyRoom(
      familyRoomId: json['family_room_id'] as String,
      createdBy: json['created_by'] as String,
      careRecipientName: json['care_recipient_name'] as String,
      createdAt: _toDateTime(json['created_at']),
      familyRoomDeletedAt: _toDateTime(
        json['family_room_deleted_at'],
      ),
      gender: (json['gender'] as num?)?.toInt(),
      birthDate: _toDateTime(json['birth_date']),
      careAddress: json['care_address'] as String?,
      latitude: _toDouble(json['latitude']),
      longitude: _toDouble(json['longitude']),
      specialNotes: json['special_notes'] as String?,
    );
  }

  // 날짜가 없는 경우에는 null을 유지한다.
  static DateTime? _toDateTime(dynamic value) {
    if (value == null) {
      return null;
    }

    return DateTime.parse(value.toString());
  }

  // 서버가 좌표를 숫자 또는 문자열로 반환해도 변환한다.
  static double? _toDouble(dynamic value) {
    if (value == null) {
      return null;
    }

    return double.parse(value.toString());
  }
}