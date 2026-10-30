import 'package:ondolbom/view/widgets/care_menu_read.dart';
import 'package:ondolbom/l10n/app_strings.dart';
import 'package:ondolbom/view/widgets/menu_header_icon.dart';
import 'package:ondolbom/view/widgets/app_add_button.dart';
import 'package:flutter/material.dart';
import 'package:ondolbom/theme/app_colors.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:ondolbom/model/memos/memo.dart';
import 'package:ondolbom/view/memos/memo_form_view.dart';
import 'package:ondolbom/view/memos/memo_image_view.dart';
import 'package:ondolbom/view/memos/memo_like_button.dart';
import 'package:ondolbom/view/memos/memo_style.dart';
import 'package:ondolbom/vm/memos/memo_vm.dart';

class MemoListView extends ConsumerWidget {
  const MemoListView({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final selected = ref.watch(memoContextProvider);
    final provider = memoVmProvider(selected);
    final feed = ref.watch(provider);
    watchCareMenuRead(
      context,
      ref,
      selected.familyRoomId,
      'memos',
      feed.hasValue && !feed.isLoading && !feed.hasError,
    );
    final canWrite =
        selected.familyRoomId.isNotEmpty && selected.userId.isNotEmpty;

    return MemoLayout(
      roomName: selected.roomName,
      title: AppStrings.tr(context, '메모'),
      action: const MenuHeaderIcon(icon: Icons.edit_outlined),
      onBack: Navigator.of(context).canPop()
          ? () => Navigator.of(context).pop()
          : null,
      floatingActionButton: AppAddButton(
        tooltip: AppStrings.tr(context, '메모 쓰기'),
        onPressed: canWrite
            ? () => Navigator.of(context).push(
                MaterialPageRoute<MemoFormResult>(
                  builder: (_) => MemoFormView(selected: selected),
                ),
              )
            : null,
      ),
      child: selected.familyRoomId.isEmpty
          ? _Message(
              icon: Icons.home_outlined,
              title: AppStrings.tr(context, '아직 선택한 돌봄 공간이 없어요'),
              description: '돌봄 공간을 연결하면 가족의 메모를 볼 수 있어요.',
            )
          : feed.when(
              skipLoadingOnRefresh: false,
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (error, _) => _Message(
                icon: Icons.wifi_off_rounded,
                title: AppStrings.tr(context, '메모를 불러오지 못했어요'),
                description: error is MemoFailure
                    ? error.message
                    : '잠시 후 다시 시도해 주세요.',
                action: OutlinedButton(
                  onPressed: () => ref.invalidate(provider),
                  child: Text(AppStrings.tr(context, '다시 시도')),
                ),
              ),
              data: (data) => RefreshIndicator(
                onRefresh: () async {
                  ref.invalidate(provider);
                  try {
                    await ref.read(provider.future);
                  } catch (_) {
                    // 오류 내용과 재시도 버튼은 위 error 화면에서 표시한다.
                  }
                },
                child: ListView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: const EdgeInsets.fromLTRB(20, 16, 20, 104),
                  children: [
                    Container(
                      padding: const EdgeInsets.all(20),
                      decoration: BoxDecoration(
                        color: AppColors.of(context).peachSoft,
                        borderRadius: BorderRadius.circular(24),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Icon(
                            Icons.auto_stories_outlined,
                            color: AppColors.of(context).sageDark,
                            size: 26,
                          ),
                          SizedBox(height: 12),
                          Text(
                            AppStrings.tr(context, '가족과 나누는 돌봄 이야기'),
                            style: TextStyle(
                              fontSize: 19,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          SizedBox(height: 6),
                          Text(
                            AppStrings.tr(
                              context,
                              '오늘의 안부와 기억하고 싶은 순간을 남겨 주세요.',
                            ),
                            style: TextStyle(
                              fontSize: 12,
                              height: 1.6,
                              color: AppColors.of(context).textPrimary,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                    if (data.items.isEmpty)
                      SizedBox(
                        height: 300,
                        child: _Message(
                          icon: Icons.edit_note_rounded,
                          title: AppStrings.tr(context, '아직 작성된 메모가 없어요'),
                          description: '가족에게 전하고 싶은 첫 이야기를 남겨 보세요.',
                        ),
                      )
                    else
                      for (final memo in data.items)
                        Card(
                          clipBehavior: Clip.antiAlias,
                          child: _MemoCard(memo: memo, selected: selected),
                        ),
                    if (data.hasMore)
                      Padding(
                        padding: const EdgeInsets.only(top: 16),
                        child: OutlinedButton(
                          onPressed: data.loadingMore
                              ? null
                              : () async {
                                  try {
                                    await ref
                                        .read(provider.notifier)
                                        .loadMore();
                                  } catch (error) {
                                    if (context.mounted) {
                                      ScaffoldMessenger.of(
                                        context,
                                      ).showSnackBar(
                                        SnackBar(
                                          content: Text(
                                            AppStrings.error(
                                              context,
                                              error is MemoFailure
                                                  ? error.message
                                                  : AppStrings.tr(
                                                      context,
                                                      '메모를 더 불러오지 못했어요.',
                                                    ),
                                            ),
                                          ),
                                        ),
                                      );
                                    }
                                  }
                                },
                          child: Text(
                            data.loadingMore
                                ? AppStrings.tr(context, '불러오는 중…')
                                : AppStrings.tr(context, '이전 메모 더 보기'),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
    );
  }
}

class _MemoCard extends StatelessWidget {
  const _MemoCard({required this.memo, required this.selected});
  final Memo memo;
  final MemoContext selected;

  @override
  Widget build(BuildContext context) => Material(
    color: Colors.transparent,
    child: InkWell(
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => MemoDetailView(memo: memo, selected: selected),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            MemoMetadata(
              author: memo.authorLabel,
              date: memo.writtenAt,
              likes: memo.likes ?? 0,
              likeButton: MemoLikeButton(memo: memo, selected: selected),
            ),
            const SizedBox(height: 12),
            _MemoPreview(content: memo.memoContent ?? ''),
            const SizedBox(height: 12),
            if (memo.hasImage) ...[
              MemoImageView(
                memo: memo,
                selected: selected,
                height: 120,
                expandable: false,
              ),
              const SizedBox(height: 12),
            ],
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerRight,
              child: Text(
                AppStrings.tr(context, '메모 읽기  →'),
                style: TextStyle(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                  fontSize: 11,
                ),
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

class _MemoPreview extends StatelessWidget {
  const _MemoPreview({required this.content});

  final String content;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final style = DefaultTextStyle.of(
        context,
      ).style.merge(const TextStyle(fontSize: 15, height: 1.65));
      final painter = TextPainter(
        textDirection: Directionality.of(context),
        textScaler: MediaQuery.textScalerOf(context),
        locale: Localizations.maybeLocaleOf(context),
        maxLines: 3,
      );
      bool fits(String text) {
        painter.text = TextSpan(text: text, style: style);
        painter.layout(maxWidth: constraints.maxWidth);
        return !painter.didExceedMaxLines;
      }

      var preview = content;
      // 명시적 줄바꿈에서도 생략 표시를 보장하고 이모지 결합 문자는 보존한다.
      if (!fits(content)) {
        final characters = content.characters.toList();
        var lower = 0;
        var upper = characters.length;
        while (lower < upper) {
          final middle = (lower + upper + 1) ~/ 2;
          if (fits('${characters.take(middle).join()}…')) {
            lower = middle;
          } else {
            upper = middle - 1;
          }
        }
        preview = '${characters.take(lower).join().trimRight()}…';
      }
      painter.dispose();
      return Text(
        preview,
        style: style,
        maxLines: 3,
        overflow: TextOverflow.ellipsis,
        semanticsLabel: content,
      );
    },
  );
}

class MemoDetailView extends ConsumerStatefulWidget {
  const MemoDetailView({super.key, required this.memo, required this.selected});
  final Memo memo;
  final MemoContext selected;

  @override
  ConsumerState<MemoDetailView> createState() => _MemoDetailViewState();
}

class _MemoDetailViewState extends ConsumerState<MemoDetailView> {
  late String _content = widget.memo.memoContent ?? '';
  late bool _hasImage = widget.memo.hasImage;
  bool _deleting = false;
  bool _finished = false;

  bool get _canManage =>
      ref.read(memoContextProvider) == widget.selected &&
      widget.selected.userId.isNotEmpty &&
      widget.memo.userId == widget.selected.userId &&
      widget.memo.familyRoomId == widget.selected.familyRoomId;

  Future<void> _edit() async {
    if (_deleting || !_canManage) return;
    // 재수정 시에도 직전에 저장한 내용을 입력창에 표시한다.
    final memo = Memo.fromJson({
      ...widget.memo.toJson(),
      'memo_content': _content,
      'has_image': _hasImage,
    });
    final result = await Navigator.of(context).push<MemoFormResult>(
      MaterialPageRoute<MemoFormResult>(
        builder: (_) => MemoFormView(selected: widget.selected, memo: memo),
      ),
    );
    if (mounted && result != null) {
      setState(() {
        _content = result.content;
        _hasImage = result.hasImage;
      });
    }
  }

  Future<void> _delete() async {
    if (_deleting || !_canManage) return;
    setState(() => _deleting = true);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(AppStrings.tr(context, '메모를 삭제할까요?')),
        content: Text(AppStrings.tr(context, '삭제한 메모는 목록에서 사라져요.')),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(AppStrings.tr(context, '취소')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(AppStrings.tr(context, '삭제하기')),
          ),
        ],
      ),
    );
    if (!mounted) return;
    if (confirmed != true || !_canManage) {
      setState(() => _deleting = false);
      return;
    }
    try {
      await ref
          .read(memoVmProvider(widget.selected).notifier)
          .deleteMemo(widget.memo);
      if (!mounted) return;
      setState(() => _finished = true);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        final messenger = ScaffoldMessenger.of(context);
        Navigator.of(context).pop();
        messenger.showSnackBar(
          SnackBar(content: Text(AppStrings.tr(context, '메모를 삭제했어요.'))),
        );
      });
    } catch (error) {
      if (!mounted) return;
      setState(() => _deleting = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            AppStrings.error(
              context,
              error is MemoFailure
                  ? error.message
                  : AppStrings.tr(context, '삭제하지 못했어요. 다시 시도해 주세요.'),
            ),
          ),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final current = ref.watch(memoContextProvider);
    ref.watch(memoVmProvider(widget.selected));
    final ownMemo =
        widget.selected.userId.isNotEmpty &&
        widget.memo.userId == widget.selected.userId &&
        widget.memo.familyRoomId == widget.selected.familyRoomId;
    return PopScope(
      canPop: !_deleting || _finished,
      child: MemoLayout(
        roomName: widget.selected.roomName,
        title: AppStrings.tr(context, '메모 상세'),
        onBack: _deleting ? null : () => Navigator.of(context).pop(),
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Card(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  MemoMetadata(
                    author: widget.memo.authorLabel,
                    date: widget.memo.writtenAt,
                    likes: widget.memo.likes ?? 0,
                    likeButton: MemoLikeButton(
                      memo: widget.memo,
                      selected: widget.selected,
                      disabled: _deleting,
                    ),
                  ),
                  const Divider(height: 32),
                  SelectableText(
                    _content,
                    style: const TextStyle(fontSize: 16, height: 1.8),
                  ),
                  if (_hasImage) ...[
                    const SizedBox(height: 16),
                    MemoImageView(memo: widget.memo, selected: widget.selected),
                  ],
                  if (ownMemo) ...[
                    const SizedBox(height: 24),
                    Wrap(
                      spacing: 12,
                      runSpacing: 8,
                      children: [
                        OutlinedButton.icon(
                          onPressed: _deleting || !_canManage ? null : _edit,
                          icon: const Icon(Icons.edit_outlined),
                          label: Text(AppStrings.tr(context, '수정')),
                        ),
                        OutlinedButton.icon(
                          onPressed: _deleting || !_canManage ? null : _delete,
                          icon: const Icon(Icons.delete_outline),
                          label: Text(
                            _deleting
                                ? AppStrings.tr(context, '삭제 중…')
                                : AppStrings.tr(context, '삭제'),
                          ),
                        ),
                      ],
                    ),
                  ],
                  if (current != widget.selected)
                    Padding(
                      padding: EdgeInsets.only(top: 12),
                      child: Text(
                        AppStrings.tr(context, '선택한 공간이 변경됐어요. 목록으로 돌아가 주세요.'),
                      ),
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

class _Message extends StatelessWidget {
  const _Message({
    required this.icon,
    required this.title,
    required this.description,
    this.action,
  });
  final IconData icon;
  final String title;
  final String description;
  final Widget? action;
  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: AppColors.of(context).peachSoft,
              shape: BoxShape.circle,
            ),
            child: Icon(icon, size: 36, color: AppColors.of(context).sageDark),
          ),
          const SizedBox(height: 18),
          Text(
            title,
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 8),
          Text(
            description,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
              height: 1.6,
            ),
          ),
          if (action != null)
            Padding(padding: const EdgeInsets.only(top: 16), child: action),
        ],
      ),
    ),
  );
}
