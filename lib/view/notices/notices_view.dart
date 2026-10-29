import 'package:ondolbom/view/widgets/menu_header_icon.dart';
import 'package:ondolbom/theme/app_colors.dart';
import 'package:ondolbom/view/widgets/activity_read_marker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:ondolbom/vm/notices/notice_vm.dart';

const _noticeInk = AppColors.textPrimary;
const _noticeMuted = AppColors.textSecondary;
const _noticePaper = AppColors.background;
const _noticeLine = AppColors.border;

// 목록·상세에서 같은 장식과 상단 배치를 사용한다.
AppBar _noticeHeader(BuildContext context, {required bool detail}) => AppBar(
  backgroundColor: _noticePaper,
  surfaceTintColor: Colors.transparent,
  foregroundColor: _noticeInk,
  toolbarHeight: 88,
  centerTitle: true,
  leadingWidth: 62,
  leading: Padding(
    padding: const EdgeInsets.only(left: 14),
    child: Center(
      child: SizedBox.square(
        dimension: 42,
        child: OutlinedButton(
          onPressed: () => Navigator.maybePop(context),
          style: OutlinedButton.styleFrom(
            padding: EdgeInsets.zero,
            backgroundColor: AppColors.surface,
            foregroundColor: _noticeInk,
            side: const BorderSide(color: _noticeLine),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(13),
            ),
          ),
          child: const Icon(Icons.chevron_left),
        ),
      ),
    ),
  ),
  title: Column(
    children: [
      const Text(
        'ONDOLBOM NEWS',
        style: TextStyle(
          color: Color(0xFFA77762),
          fontSize: 8,
          fontWeight: FontWeight.w800,
          letterSpacing: 1.3,
        ),
      ),
      const SizedBox(height: 3),
      Text(
        detail ? '공지 상세' : '공지사항',
        style: const TextStyle(
          color: _noticeInk,
          fontSize: 24,
          fontWeight: FontWeight.w800,
        ),
      ),
    ],
  ),
  actions: const [
    MenuHeaderIcon(
      icon: Icons.campaign_outlined,
      backgroundColor: AppColors.peachLight,
      foregroundColor: Color(0xFF875C49),
    ),
  ],
);

BoxDecoration _noticeCardDecoration() => BoxDecoration(
  color: AppColors.surface,
  border: Border.all(color: _noticeLine),
  borderRadius: BorderRadius.circular(22),
  boxShadow: [
    BoxShadow(
      color: const Color(0xFF594135).withValues(alpha: 0.04),
      blurRadius: 24,
      offset: const Offset(0, 8),
    ),
  ],
);

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
      backgroundColor: _noticePaper,
      appBar: _noticeHeader(context, detail: false),
      body: result.when(
        loading: () => const Center(
          child: CircularProgressIndicator(color: AppColors.primary),
        ),
        error: (error, _) => NoticeError(
          message: error.toString(),
          retry: () => ref.invalidate(noticesProvider(_offset)),
        ),
        data: (page) => Align(
          alignment: Alignment.topCenter,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 560),
            child: ListView(
              padding: const EdgeInsets.fromLTRB(20, 24, 20, 32),
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    const Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '온돌봄의 새로운 소식',
                            style: TextStyle(color: _noticeMuted, fontSize: 12),
                          ),
                          SizedBox(height: 7),
                          Text(
                            '꼭 확인해 주세요',
                            style: TextStyle(
                              color: _noticeInk,
                              fontSize: 24,
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
                        vertical: 8,
                      ),
                      decoration: BoxDecoration(
                        color: AppColors.peachSoft,
                        borderRadius: BorderRadius.circular(24),
                      ),
                      child: Text(
                        '${page.items.length}개의 공지${page.hasMore || _offset > 0 ? ' · 현재 페이지' : ''}',
                        style: const TextStyle(
                          color: Color(0xFFA46F59),
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 24),
                if (page.items.isEmpty)
                  const Padding(
                    padding: EdgeInsets.all(32),
                    child: Text('등록된 공지사항이 없습니다.', textAlign: TextAlign.center),
                  ),
                for (final notice in page.items)
                  Container(
                    margin: const EdgeInsets.only(bottom: 14),
                    decoration: _noticeCardDecoration(),
                    child: Material(
                      color: Colors.transparent,
                      borderRadius: BorderRadius.circular(22),
                      clipBehavior: Clip.antiAlias,
                      child: InkWell(
                        onTap: () => Navigator.of(context).push(
                          MaterialPageRoute<void>(
                            builder: (_) => NoticeDetailView(
                              noticeKey: (
                                adminId: notice.adminId,
                                id: notice.id,
                              ),
                            ),
                          ),
                        ),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 24,
                          ),
                          child: Row(
                            children: [
                              Container(
                                width: 42,
                                height: 42,
                                decoration: BoxDecoration(
                                  color: AppColors.peachSoft,
                                  borderRadius: BorderRadius.circular(14),
                                ),
                                child: const Icon(
                                  Icons.campaign_outlined,
                                  size: 22,
                                  color: Color(0xFFA46F59),
                                ),
                              ),
                              const SizedBox(width: 13),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      notice.createdAt.toString().substring(
                                        0,
                                        16,
                                      ),
                                      style: const TextStyle(
                                        color: _noticeMuted,
                                        fontSize: 10,
                                      ),
                                    ),
                                    const SizedBox(height: 8),
                                    Text(
                                      notice.title,
                                      style: const TextStyle(
                                        color: _noticeInk,
                                        fontSize: 16,
                                        fontWeight: FontWeight.w800,
                                        height: 1.45,
                                      ),
                                    ),
                                    const SizedBox(height: 6),
                                    Text(
                                      notice.content
                                          .replaceAll(RegExp(r'\s+'), ' ')
                                          .trim(),
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(
                                        color: _noticeMuted,
                                        fontSize: 12,
                                        height: 1.6,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(width: 8),
                              const Icon(
                                Icons.chevron_right,
                                size: 19,
                                color: Color(0xFFB1A59F),
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
                      onPressed: _offset == 0
                          ? null
                          : () => setState(() => _offset -= 30),
                      style: TextButton.styleFrom(foregroundColor: _noticeInk),
                      child: const Text('이전'),
                    ),
                    TextButton(
                      onPressed: page.hasMore
                          ? () => setState(() => _offset += 30)
                          : null,
                      style: TextButton.styleFrom(foregroundColor: _noticeInk),
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

class NoticeDetailView extends ConsumerWidget {
  const NoticeDetailView({super.key, required this.noticeKey});
  final NoticeKey noticeKey;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final result = ref.watch(noticeDetailProvider(noticeKey));
    return Scaffold(
      backgroundColor: _noticePaper,
      appBar: _noticeHeader(context, detail: true),
      body: result.when(
        loading: () => const Center(
          child: CircularProgressIndicator(color: AppColors.primary),
        ),
        error: (e, _) => NoticeError(
          message: e.toString(),
          retry: () => ref.invalidate(noticeDetailProvider(noticeKey)),
        ),
        data: (notice) => ActivityReadMarker(
          path:
              '/notices/${Uri.encodeComponent(notice.adminId)}/${Uri.encodeComponent(notice.id)}',
          token: notice.badgeToken,
          child: Align(
            alignment: Alignment.topCenter,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 560),
              child: ListView(
                padding: const EdgeInsets.fromLTRB(20, 24, 20, 32),
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 22,
                      vertical: 30,
                    ),
                    decoration: _noticeCardDecoration(),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          notice.title,
                          style: const TextStyle(
                            color: _noticeInk,
                            fontSize: 25,
                            fontWeight: FontWeight.w800,
                            height: 1.4,
                            letterSpacing: -0.8,
                          ),
                        ),
                        const SizedBox(height: 16),
                        Row(
                          children: [
                            const Icon(
                              Icons.schedule,
                              size: 14,
                              color: _noticeMuted,
                            ),
                            const SizedBox(width: 7),
                            Expanded(
                              child: Text(
                                '등록 ${notice.createdAt.toString().substring(0, 16)}',
                                style: const TextStyle(
                                  color: _noticeMuted,
                                  fontSize: 11,
                                ),
                              ),
                            ),
                          ],
                        ),
                        if (notice.updatedAt != null)
                          Padding(
                            padding: const EdgeInsets.only(top: 7),
                            child: Text(
                              '수정 ${notice.updatedAt.toString().substring(0, 16)}',
                              style: const TextStyle(
                                color: _noticeMuted,
                                fontSize: 11,
                              ),
                            ),
                          ),
                        const Divider(color: Color(0xFFF0E6DF), height: 42),
                        SelectableText(
                          notice.content,
                          style: const TextStyle(
                            color: Color(0xFF746A64),
                            fontSize: 15,
                            height: 1.9,
                          ),
                        ),
                        const SizedBox(height: 32),
                        const Text(
                          '온돌봄 운영팀 드림',
                          style: TextStyle(
                            color: Color(0xFFA46F59),
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 22),
                  FilledButton(
                    onPressed: () => Navigator.maybePop(context),
                    style: FilledButton.styleFrom(
                      backgroundColor: AppColors.primary,
                      foregroundColor: _noticeInk,
                      minimumSize: const Size.fromHeight(54),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                      textStyle: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    child: const Text('목록으로 돌아가기'),
                  ),
                ],
              ),
            ),
          ),
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
