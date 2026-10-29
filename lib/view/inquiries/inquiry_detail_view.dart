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
      appBar: AppBar(
        title: const Text('문의 상세'),
        actions: [
          IconButton(
            tooltip: '답변 새로고침',
            onPressed: () => ref.invalidate(inquiryDetailProvider(id)),
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: inquiry.when(
        loading: () => const Center(child: CircularProgressIndicator()),
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
        data: (item) => ListView(
          padding: const EdgeInsets.all(24),
          children: [
            Text(item.title, style: Theme.of(context).textTheme.headlineSmall),
            const SizedBox(height: 8),
            Text(
              '${item.answered ? '답변 완료' : '답변 대기'} · ${item.createdAt.toString().substring(0, 16)}',
            ),
            if (item.familyRoomId != null)
              const Padding(
                padding: EdgeInsets.only(top: 8),
                child: Text('가족 공간 관련 문의'),
              ),
            const SizedBox(height: 24),
            SelectableText(item.content ?? ''),
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 24),
              child: Divider(),
            ),
            Text('관리자 답변', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 16),
            if (item.answers.isEmpty) const Text('아직 등록된 답변이 없습니다.'),
            for (final answer in item.answers)
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(answer.createdAt.toString().substring(0, 16)),
                      const SizedBox(height: 12),
                      SelectableText(answer.content),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
