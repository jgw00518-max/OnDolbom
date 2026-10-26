import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:ondolbom/view/inquiries/inquiry_form_view.dart';
import 'package:ondolbom/view/inquiries/inquiry_detail_view.dart';
import 'package:ondolbom/vm/inquiries/inquiry_vm.dart';

class InquiriesView extends ConsumerStatefulWidget {
  const InquiriesView({super.key, this.familyRoomId});
  final String? familyRoomId;
  @override
  ConsumerState<InquiriesView> createState() => _InquiriesViewState();
}

class _InquiriesViewState extends ConsumerState<InquiriesView> {
  final _cursors = <int?>[null];
  @override
  Widget build(BuildContext context) {
    final cursor = _cursors.last;
    final page = ref.watch(inquiriesProvider(cursor));
    return Scaffold(
      appBar: AppBar(
        title: const Text('내 문의'),
        actions: [
          IconButton(
            tooltip: '문의 새로고침',
            onPressed: () => ref.invalidate(inquiriesProvider(cursor)),
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        icon: const Icon(Icons.edit_outlined),
        label: const Text('문의 작성'),
        onPressed: () async {
          final id = await Navigator.of(context).push<int>(
            MaterialPageRoute(
              builder: (_) =>
                  InquiryFormView(familyRoomId: widget.familyRoomId),
            ),
          );
          if (!mounted || id == null) return;
          setState(() {
            _cursors.clear();
            _cursors.add(null);
          });
          ref.invalidate(inquiriesProvider);
          if (!context.mounted) return;
          Navigator.of(context).push(
            MaterialPageRoute<void>(builder: (_) => InquiryDetailView(id: id)),
          );
        },
      ),
      body: page.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(error.toString()),
              TextButton(
                onPressed: () => ref.invalidate(inquiriesProvider(cursor)),
                child: const Text('다시 시도'),
              ),
            ],
          ),
        ),
        data: (value) => ListView(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 110),
          children: [
            const Text('작성한 문의는 본인과 관리자만 확인할 수 있습니다.'),
            const SizedBox(height: 16),
            if (value.items.isEmpty)
              const Padding(
                padding: EdgeInsets.all(32),
                child: Text('등록한 문의가 없습니다.', textAlign: TextAlign.center),
              ),
            for (final item in value.items)
              Card(
                child: ListTile(
                  title: Text(item.title),
                  subtitle: Text(
                    '${item.answered ? '답변 완료' : '답변 대기'} · ${item.createdAt.toString().substring(0, 16)}',
                  ),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => InquiryDetailView(id: item.id),
                    ),
                  ),
                ),
              ),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                TextButton(
                  onPressed: _cursors.length > 1
                      ? () => setState(() {
                          _cursors.removeLast();
                        })
                      : null,
                  child: const Text('이전'),
                ),
                TextButton(
                  onPressed: value.nextCursor == null
                      ? null
                      : () => setState(() => _cursors.add(value.nextCursor)),
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
