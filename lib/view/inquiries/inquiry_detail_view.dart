import 'package:ondolbom/theme/app_colors.dart';
import 'package:ondolbom/view/inquiries/inquiry_style.dart';
import 'package:ondolbom/view/widgets/activity_read_marker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:ondolbom/vm/inquiries/inquiry_vm.dart';

class InquiryDetailView extends ConsumerWidget {
  const InquiryDetailView({super.key, required this.id});
  final int id;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final inquiry = ref.watch(inquiryDetailProvider(id));
    return Scaffold(
      backgroundColor: InquiryStyle.paper,
      appBar: InquiryStyle.header(
        context,
        '문의 상세',
        refreshLabel: '답변 새로고침',
        refresh: () => ref.invalidate(inquiryDetailProvider(id)),
      ),
      body: inquiry.when(
        loading: () => const Center(
          child: CircularProgressIndicator(color: InquiryStyle.peach),
        ),
        error: (e, _) => Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(e.toString()),
              TextButton(
                onPressed: () => ref.invalidate(inquiryDetailProvider(id)),
                child: const Text('다시 시도'),
              ),
            ],
          ),
        ),
        data: (item) => ActivityReadMarker(
          path: '/inquiries/${item.id}',
          token: item.badgeToken,
          child: Align(
            alignment: Alignment.topCenter,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 560),
              child: ListView(
                padding: const EdgeInsets.fromLTRB(24, 28, 24, 40),
                children: [
                  Align(
                    alignment: Alignment.centerLeft,
                    child: InquiryStyle.status(item.answered),
                  ),
                  const SizedBox(height: 18),
                  Text(
                    item.title,
                    style: const TextStyle(
                      color: InquiryStyle.ink,
                      fontSize: 25,
                      fontWeight: FontWeight.w800,
                      height: 1.4,
                      letterSpacing: -0.8,
                    ),
                  ),
                  const SizedBox(height: 14),
                  Row(
                    children: [
                      const Icon(
                        Icons.schedule,
                        color: InquiryStyle.muted,
                        size: 14,
                      ),
                      const SizedBox(width: 7),
                      Expanded(
                        child: Text(
                          item.createdAt.toString().substring(0, 16),
                          style: const TextStyle(
                            color: InquiryStyle.muted,
                            fontSize: 11,
                          ),
                        ),
                      ),
                    ],
                  ),
                  if (item.familyRoomId != null)
                    const Padding(
                      padding: EdgeInsets.only(top: 10),
                      child: Text(
                        '가족 공간 관련 문의',
                        style: TextStyle(
                          color: InquiryStyle.muted,
                          fontSize: 12,
                        ),
                      ),
                    ),
                  const Divider(color: Color(0xFFF0E6DF), height: 42),
                  const Text(
                    '문의 내용',
                    style: TextStyle(
                      color: Color(0xFFA46F59),
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 16),
                  SelectableText(
                    item.content ?? '',
                    style: const TextStyle(
                      color: Color(0xFF746A64),
                      fontSize: 15,
                      height: 1.9,
                    ),
                  ),
                  const Divider(color: Color(0xFFF0E6DF), height: 42),
                  // 답변의 개수와 원문은 실제 서버 응답을 유지한다.
                  if (item.answers.isEmpty) _answerCard(null, null),
                  for (final answer in item.answers)
                    _answerCard(answer.content, answer.createdAt),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _answerCard(String? content, DateTime? date) => Container(
    padding: const EdgeInsets.all(20),
    margin: const EdgeInsets.only(bottom: 16),
    decoration: BoxDecoration(
      color: const Color(0xFFFFF6EF),
      border: Border.all(color: const Color(0xFFF1C1A8)),
      borderRadius: BorderRadius.circular(20),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                color: AppColors.peachLight,
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Icon(
                Icons.chat_outlined,
                size: 20,
                color: Color(0xFF875C49),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    '관리자 답변',
                    style: TextStyle(
                      color: InquiryStyle.ink,
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  if (date != null) ...[
                    const SizedBox(height: 4),
                    Text(
                      date.toString().substring(0, 16),
                      style: const TextStyle(
                        color: InquiryStyle.muted,
                        fontSize: 10,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        SelectableText(
          content ?? '아직 등록된 답변이 없습니다.',
          style: const TextStyle(
            color: Color(0xFF746A64),
            fontSize: 14,
            height: 1.9,
          ),
        ),
      ],
    ),
  );
}
