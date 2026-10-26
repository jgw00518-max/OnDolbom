class InquiryAnswer {
  const InquiryAnswer({required this.content, required this.createdAt});
  final String content;
  final DateTime createdAt;
  factory InquiryAnswer.fromJson(Map<String, dynamic> json) => InquiryAnswer(
    content: json['answer_content'] as String,
    createdAt: DateTime.parse(json['answered_at'] as String),
  );
}

class Inquiry {
  const Inquiry({
    required this.id,
    required this.title,
    required this.createdAt,
    required this.answered,
    this.content,
    this.familyRoomId,
    this.answers = const [],
  });
  final int id;
  final String title;
  final String? content;
  final String? familyRoomId;
  final DateTime createdAt;
  final bool answered;
  final List<InquiryAnswer> answers;
  factory Inquiry.fromJson(Map<String, dynamic> json) => Inquiry(
    id: (json['question_seq'] as num).toInt(),
    title: json['question_title'] as String,
    content: json['question_content'] as String?,
    familyRoomId: json['family_room_id'] as String?,
    createdAt: DateTime.parse(json['questioned_at'] as String),
    answered: json['answered'] == true || json['answered'] == 1,
    answers: (json['answers'] as List<dynamic>? ?? [])
        .map((a) => InquiryAnswer.fromJson(a as Map<String, dynamic>))
        .toList(),
  );
}
