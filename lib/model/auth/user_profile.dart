class UserProfile {
  const UserProfile({required this.userId, this.email, this.name, this.phone});
  final String userId;
  final String? email;
  final String? name;
  final String? phone;

  factory UserProfile.fromJson(Map<String, dynamic> json) => UserProfile(
    userId: json['user_id'] as String,
    email: json['user_email'] as String?,
    name: json['name'] as String?,
    phone: json['phone'] as String?,
  );
}
