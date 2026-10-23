/// Firebase 인증 사용자. MySQL 가족 프로필과는 별도다.
class AppUser {
  const AppUser({required this.uid, this.email});
  final String uid;
  final String? email;
}
