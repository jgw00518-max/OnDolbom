import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:ondolbom/model/memos/memo.dart';
import 'package:ondolbom/view/memos/memo_form_view.dart';
import 'package:ondolbom/view/memos/memo_style.dart';
import 'package:ondolbom/vm/memos/memo_vm.dart';

class MemoListView extends ConsumerWidget {
  const MemoListView({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final selected = ref.watch(memoContextProvider);
    final provider = memoVmProvider(selected);
    final feed = ref.watch(provider);
    final canWrite =
        selected.familyRoomId.isNotEmpty && selected.userId.isNotEmpty;

    return MemoLayout(
      roomName: selected.roomName,
      title: '메모',
      action: FilledButton.tonal(
        onPressed: canWrite
            ? () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => MemoFormView(selected: selected),
                ),
              )
            : null,
        child: const Text('메모 쓰기'),
      ),
      child: selected.familyRoomId.isEmpty
          ? const _Message(
              icon: Icons.home_outlined,
              title: '아직 선택한 돌봄 공간이 없어요',
              description: '돌봄 공간을 연결하면 가족의 메모를 볼 수 있어요.',
            )
          : feed.when(
              skipLoadingOnRefresh: false,
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (error, _) => _Message(
                icon: Icons.wifi_off_rounded,
                title: '메모를 불러오지 못했어요',
                description: error is MemoFailure
                    ? error.message
                    : '잠시 후 다시 시도해 주세요.',
                action: OutlinedButton(
                  onPressed: () => ref.invalidate(provider),
                  child: const Text('다시 시도'),
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
                  padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
                  children: [
                    Text(
                      '가족과 나누는 돌봄 이야기',
                      style: TextStyle(
                        color: memoBrown.withValues(alpha: 0.8),
                        fontSize: 13,
                      ),
                    ),
                    const SizedBox(height: 16),
                    if (data.items.isEmpty)
                      const SizedBox(
                        height: 300,
                        child: _Message(
                          icon: Icons.edit_note_rounded,
                          title: '아직 작성된 메모가 없어요',
                          description: '가족에게 전하고 싶은 첫 이야기를 남겨 보세요.',
                        ),
                      )
                    else
                      Container(
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(22),
                          border: Border.all(color: const Color(0xFFEDE9E3)),
                        ),
                        clipBehavior: Clip.antiAlias,
                        child: Column(
                          children: [
                            for (var i = 0; i < data.items.length; i++) ...[
                              if (i > 0)
                                const Padding(
                                  padding: EdgeInsets.symmetric(horizontal: 20),
                                  child: Divider(height: 1),
                                ),
                              _MemoCard(
                                memo: data.items[i],
                                selected: selected,
                              ),
                            ],
                          ],
                        ),
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
                                            error is MemoFailure
                                                ? error.message
                                                : '메모를 더 불러오지 못했어요.',
                                          ),
                                        ),
                                      );
                                    }
                                  }
                                },
                          child: Text(
                            data.loadingMore ? '불러오는 중…' : '이전 메모 더 보기',
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
            Text(
              memo.memoContent ?? '',
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 15, height: 1.65),
            ),
            const SizedBox(height: 12),
            MemoMetadata(
              author: memo.userId == selected.userId ? '나' : memo.userId,
              date: memo.writtenAt,
              likes: memo.likes ?? 0,
            ),
            const SizedBox(height: 8),
            const Align(
              alignment: Alignment.centerRight,
              child: Text(
                '눌러서 자세히 보기',
                style: TextStyle(color: memoMuted, fontSize: 11),
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

class MemoDetailView extends StatelessWidget {
  const MemoDetailView({super.key, required this.memo, required this.selected});
  final Memo memo;
  final MemoContext selected;

  @override
  Widget build(BuildContext context) => MemoLayout(
    roomName: selected.roomName,
    title: '메모 상세',
    onBack: () => Navigator.of(context).pop(),
    child: SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(22),
          border: Border.all(color: const Color(0xFFEDE9E3)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            MemoMetadata(
              author: memo.userId == selected.userId ? '나' : memo.userId,
              date: memo.writtenAt,
              likes: memo.likes ?? 0,
            ),
            const Divider(height: 36),
            SelectableText(
              memo.memoContent ?? '',
              style: const TextStyle(fontSize: 16, height: 1.8),
            ),
          ],
        ),
      ),
    ),
  );
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
          Icon(icon, size: 42, color: memoBrown),
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
            style: const TextStyle(color: memoMuted, height: 1.6),
          ),
          if (action != null)
            Padding(padding: const EdgeInsets.only(top: 16), child: action),
        ],
      ),
    ),
  );
}
