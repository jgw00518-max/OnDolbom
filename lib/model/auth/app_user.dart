/// Firebase 인증 사용자. MySQL 가족 프로필과는 별도다.
class AppUser {
  const AppUser({required this.uid, this.email});
  // Firebase 계정 식별자이며 MySQL의 내부 user_id와는 다른 값이다.
  final String uid;
  final String? email;
}
