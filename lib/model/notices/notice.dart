class Notice {
  const Notice({
    required this.adminId,
    required this.id,
    required this.title,
    required this.content,
    required this.createdAt,
    this.updatedAt,
    this.badgeToken,
  });
  final String adminId, id, title, content;
  final DateTime createdAt;
  final DateTime? updatedAt;
  final String? badgeToken;
  factory Notice.fromJson(Map<String, dynamic> json) => Notice(
    adminId: json['admin_id'] as String,
    id: json['notice_id'] as String,
    title: json['notice_title'] as String,
    badgeToken: json['badge_token'] as String?,
    content: json['notice_content'] as String,
    createdAt: DateTime.parse(json['notice_created_at'] as String),
    updatedAt: json['notice_updated_at'] == null
        ? null
        : DateTime.parse(json['notice_updated_at'] as String),
  );
}
