import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:ondolbom/vm/notices/notice_vm.dart';

class NoticesView extends ConsumerStatefulWidget {
  const NoticesView({super.key});
  @override
  ConsumerState<NoticesView> createState() => _NoticesViewState();
}

class _NoticesViewState extends ConsumerState<NoticesView> {
  int _offset = 0;
  @override
  Widget build(BuildContext context) {
    final result = ref.watch(noticesProvider(_offset));
    return Scaffold(
      appBar: AppBar(
        title: const Text('공지사항'),
        actions: [
          IconButton(
            tooltip: '공지 새로고침',
            onPressed: () => ref.invalidate(noticesProvider(_offset)),
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: result.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => NoticeError(
          message: error.toString(),
          retry: () => ref.invalidate(noticesProvider(_offset)),
        ),
        data: (page) => ListView(
          padding: const EdgeInsets.all(20),
          children: [
            if (page.items.isEmpty)
              const Padding(
                padding: EdgeInsets.all(32),
                child: Text('등록된 공지사항이 없습니다.', textAlign: TextAlign.center),
              ),
            for (final notice in page.items)
              Card(
                child: ListTile(
                  title: Text(notice.title),
                  subtitle: Text(notice.createdAt.toString().substring(0, 16)),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => NoticeDetailView(
                        noticeKey: (adminId: notice.adminId, id: notice.id),
                      ),
                    ),
                  ),
                ),
              ),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                TextButton(
                  onPressed: _offset == 0
                      ? null
                      : () => setState(() => _offset -= 30),
                  child: const Text('이전'),
                ),
                TextButton(
                  onPressed: page.hasMore
                      ? () => setState(() => _offset += 30)
                      : null,
                  child: const Text('다음'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class NoticeDetailView extends ConsumerWidget {
  const NoticeDetailView({super.key, required this.noticeKey});
  final NoticeKey noticeKey;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final result = ref.watch(noticeDetailProvider(noticeKey));
    return Scaffold(
      appBar: AppBar(
        title: const Text('공지 상세'),
        actions: [
          IconButton(
            tooltip: '공지 상세 새로고침',
            onPressed: () => ref.invalidate(noticeDetailProvider(noticeKey)),
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: result.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => NoticeError(
          message: e.toString(),
          retry: () => ref.invalidate(noticeDetailProvider(noticeKey)),
        ),
        data: (notice) => ListView(
          padding: const EdgeInsets.all(24),
          children: [
            Text(
              notice.title,
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            const SizedBox(height: 12),
            Text('등록 ${notice.createdAt.toString().substring(0, 16)}'),
            if (notice.updatedAt != null)
              Text('수정 ${notice.updatedAt.toString().substring(0, 16)}'),
            const Divider(height: 32),
            SelectableText(notice.content),
          ],
        ),
      ),
    );
  }
}

class NoticeError extends StatelessWidget {
  const NoticeError({super.key, required this.message, required this.retry});
  final String message;
  final VoidCallback retry;
  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(message, textAlign: TextAlign.center),
          TextButton(onPressed: retry, child: const Text('다시 시도')),
        ],
      ),
    ),
  );
}
