import 'package:ondolbom/theme/app_colors.dart';
import 'package:ondolbom/view/inquiries/inquiry_style.dart';
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
      backgroundColor: InquiryStyle.paper,
      appBar: InquiryStyle.header(context, '내 문의'),
      floatingActionButton: FloatingActionButton.extended(
        foregroundColor: InquiryStyle.ink,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
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
        loading: () => const Center(
          child: CircularProgressIndicator(color: InquiryStyle.peach),
        ),
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
        data: (value) => Align(
          alignment: Alignment.topCenter,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 560),
            child: ListView(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 110),
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    const Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '나와 관리자만 확인할 수 있어요',
                            style: TextStyle(
                              color: InquiryStyle.muted,
                              fontSize: 12,
                            ),
                          ),
                          SizedBox(height: 7),
                          Text(
                            '문의 내역',
                            style: TextStyle(
                              color: InquiryStyle.ink,
                              fontSize: 25,
                              fontWeight: FontWeight.w800,
                              letterSpacing: -0.8,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 7,
                      ),
                      decoration: BoxDecoration(
                        color: AppColors.peachSoft,
                        borderRadius: BorderRadius.circular(24),
                      ),
                      child: Text(
                        '${value.items.length}건${value.nextCursor != null || _cursors.length > 1 ? ' · 현재 페이지' : ''}',
                        style: const TextStyle(
                          color: Color(0xFFA46F59),
                          fontSize: 11,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 24),
                if (value.items.isEmpty)
                  const Padding(
                    padding: EdgeInsets.all(32),
                    child: Text('등록한 문의가 없습니다.', textAlign: TextAlign.center),
                  ),
                for (final item in value.items)
                  Container(
                    margin: const EdgeInsets.only(bottom: 14),
                    decoration: BoxDecoration(
                      color: AppColors.surface,
                      borderRadius: BorderRadius.circular(22),
                      border: Border.all(color: InquiryStyle.line),
                      boxShadow: [
                        BoxShadow(
                          color: const Color(
                            0xFF594135,
                          ).withValues(alpha: 0.04),
                          blurRadius: 24,
                          offset: const Offset(0, 8),
                        ),
                      ],
                    ),
                    child: Material(
                      color: Colors.transparent,
                      borderRadius: BorderRadius.circular(22),
                      clipBehavior: Clip.antiAlias,
                      child: InkWell(
                        onTap: () => Navigator.of(context).push(
                          MaterialPageRoute<void>(
                            builder: (_) => InquiryDetailView(id: item.id),
                          ),
                        ),
                        child: Padding(
                          padding: const EdgeInsets.all(20),
                          child: Row(
                            children: [
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    InquiryStyle.status(item.answered),
                                    const SizedBox(height: 14),
                                    Text(
                                      item.title,
                                      style: const TextStyle(
                                        color: InquiryStyle.ink,
                                        fontSize: 17,
                                        fontWeight: FontWeight.w800,
                                        height: 1.5,
                                      ),
                                    ),
                                    const SizedBox(height: 9),
                                    Text(
                                      item.createdAt.toString().substring(
                                        0,
                                        16,
                                      ),
                                      style: const TextStyle(
                                        color: InquiryStyle.muted,
                                        fontSize: 11,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(width: 10),
                              const Icon(
                                Icons.chevron_right,
                                color: Color(0xFFB1A59F),
                                size: 21,
                              ),
                            ],
                          ),
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
                          : () =>
                                setState(() => _cursors.add(value.nextCursor)),
                      child: const Text('다음'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
