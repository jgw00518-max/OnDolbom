import 'package:ondolbom/l10n/app_strings.dart';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:ondolbom/model/memos/memo.dart';
import 'package:ondolbom/vm/memos/memo_vm.dart';

class MemoLikeButton extends ConsumerWidget {
  const MemoLikeButton({
    super.key,
    required this.memo,
    required this.selected,
    this.disabled = false,
  });
  final Memo memo;
  final MemoContext selected;
  final bool disabled;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final provider = memoLikeProvider((
      context: selected,
      memoId: memo.memoId,
      authorId: memo.userId,
    ));
    final action = ref.watch(provider);
    final result = action.asData?.value;
    final liked = memo.isLiked || result != null;
    final likes = math.max(memo.likes ?? 0, result?.likes ?? 0);
    final allowed =
        ref.watch(memoContextProvider) == selected &&
        selected.userId.isNotEmpty &&
        memo.familyRoomId == selected.familyRoomId;
    return Tooltip(
      message: liked
          ? AppStrings.tr(context, '좋아요를 눌렀어요. 취소할 수 없어요.')
          : AppStrings.tr(context, '좋아요'),
      child: TextButton.icon(
        onPressed: disabled || !allowed || liked || action.isLoading
            ? null
            : () async {
                try {
                  await ref.read(provider.notifier).like(memo);
                } catch (error) {
                  if (!context.mounted) return;
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(
                        AppStrings.error(
                          context,
                          error is MemoFailure
                              ? error.message
                              : AppStrings.tr(
                                  context,
                                  '좋아요를 등록하지 못했어요. 다시 시도해 주세요.',
                                ),
                        ),
                      ),
                    ),
                  );
                }
              },
        icon: action.isLoading
            ? const SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : Icon(
                liked ? Icons.favorite : Icons.favorite_border,
                size: 18,
                color: liked ? Theme.of(context).colorScheme.primary : null,
              ),
        label: Text(AppStrings.format(context, "좋아요 {0}", [likes])),
      ),
    );
  }
}
