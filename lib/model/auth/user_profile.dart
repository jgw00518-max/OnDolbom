/// 서버가 검증한 Firebase 계정에 연결된 MySQL 가족 프로필.
class UserProfile {
  const UserProfile({required this.userId, this.email, this.name, this.phone});
  // 일정·공간 등 MySQL 관계에서 사용하는 내부 사용자 ID.
  final String userId;
  // 기존 DB 행은 NULL일 수 있어 조회 모델에서도 nullable로 유지한다.
  final String? email;
  final String? name;
  final String? phone;

  // 서버 응답의 실제 컬럼 이름을 Dart 필드에 매핑한다. 비밀번호는 받지 않는다.
  factory UserProfile.fromJson(Map<String, dynamic> json) => UserProfile(
    userId: json['user_id'] as String,
    email: json['user_email'] as String?,
    name: json['name'] as String?,
    phone: json['phone'] as String?,
  );
}
