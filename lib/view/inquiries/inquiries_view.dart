import 'package:ondolbom/view/widgets/app_empty_state.dart';
import 'package:ondolbom/l10n/app_strings.dart';
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
      backgroundColor: AppColors.resolve(context, InquiryStyle.paper),
      appBar: InquiryStyle.header(context, AppStrings.tr(context, '내 문의')),
      floatingActionButton: FloatingActionButton.extended(
        foregroundColor: AppColors.resolve(context, InquiryStyle.ink),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        icon: const Icon(Icons.edit_outlined),
        label: Text(AppStrings.tr(context, '문의 작성')),
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
        loading: () => Center(
          child: CircularProgressIndicator(
            color: AppColors.resolve(context, InquiryStyle.peach),
          ),
        ),
        error: (error, _) => Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(AppStrings.error(context, error.toString())),
              TextButton(
                onPressed: () => ref.invalidate(inquiriesProvider(cursor)),
                child: Text(AppStrings.tr(context, '다시 시도')),
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
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            AppStrings.tr(context, '나와 관리자만 확인할 수 있어요'),
                            style: TextStyle(
                              color: AppColors.resolve(
                                context,
                                InquiryStyle.muted,
                              ),
                              fontSize: 12,
                            ),
                          ),
                          SizedBox(height: 7),
                          Text(
                            AppStrings.tr(context, '문의 내역'),
                            style: TextStyle(
                              color: AppColors.resolve(
                                context,
                                InquiryStyle.ink,
                              ),
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
                        color: AppColors.of(context).peachSoft,
                        borderRadius: BorderRadius.circular(24),
                      ),
                      child: Text(
                        AppStrings.format(context, "{0}건{1}", [
                          value.items.length,
                          value.nextCursor != null || _cursors.length > 1
                              ? ' · 현재 페이지'
                              : '',
                        ]),
                        style: TextStyle(
                          color: AppColors.resolve(context, Color(0xFFA46F59)),
                          fontSize: 11,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 24),
                if (value.items.isEmpty)
                  const SizedBox(
                    height: 300,
                    child: AppEmptyState(
                      icon: Icons.help_outline_rounded,
                      title: '등록한 문의가 없습니다.',
                      description: '궁금한 점이 있다면 첫 문의를 남겨 보세요.',
                    ),
                  ),
                for (final item in value.items)
                  Container(
                    margin: const EdgeInsets.only(bottom: 14),
                    decoration: BoxDecoration(
                      color: AppColors.of(context).surface,
                      borderRadius: BorderRadius.circular(22),
                      border: Border.all(
                        color: AppColors.resolve(context, InquiryStyle.line),
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: AppColors.resolve(
                            context,
                            const Color(0xFF594135),
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
                                    InquiryStyle.status(context, item.answered),
                                    const SizedBox(height: 14),
                                    Text(
                                      item.title,
                                      style: TextStyle(
                                        color: AppColors.resolve(
                                          context,
                                          InquiryStyle.ink,
                                        ),
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
                                      style: TextStyle(
                                        color: AppColors.resolve(
                                          context,
                                          InquiryStyle.muted,
                                        ),
                                        fontSize: 11,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(width: 10),
                              Icon(
                                Icons.chevron_right,
                                color: AppColors.resolve(
                                  context,
                                  Color(0xFFB1A59F),
                                ),
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
                      child: Text(AppStrings.tr(context, '이전')),
                    ),
                    TextButton(
                      onPressed: value.nextCursor == null
                          ? null
                          : () =>
                                setState(() => _cursors.add(value.nextCursor)),
                      child: Text(AppStrings.tr(context, '다음')),
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
