import 'package:ondolbom/l10n/app_strings.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:ondolbom/model/memos/memo.dart';
import 'package:ondolbom/vm/memos/memo_vm.dart';

class MemoImageView extends ConsumerWidget {
  const MemoImageView({
    super.key,
    required this.memo,
    required this.selected,
    this.height = 220,
    this.expandable = true,
    this.zoomable = false,
  });
  final Memo memo;
  final MemoContext selected;
  final double height;
  final bool expandable;
  final bool zoomable;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final provider = memoImageProvider((
      context: selected,
      memoId: memo.memoId,
      authorId: memo.userId,
    ));
    return SizedBox(
      height: height,
      width: double.infinity,
      child: ref
          .watch(provider)
          .when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (error, _) => Center(
              child: TextButton.icon(
                onPressed: () => ref.invalidate(provider),
                icon: const Icon(Icons.refresh),
                label: Text(AppStrings.tr(context, '사진 다시 불러오기')),
              ),
            ),
            data: (bytes) {
              final image = Image.memory(
                bytes,
                fit: BoxFit.contain,
                cacheWidth: zoomable ? null : 800,
                errorBuilder: (_, _, _) => Center(
                  child: Text(AppStrings.tr(context, '사진을 표시할 수 없어요.')),
                ),
              );
              if (!expandable) {
                return zoomable
                    ? InteractiveViewer(maxScale: 5, child: image)
                    : image;
              }
              return Semantics(
                label: AppStrings.tr(context, '첨부 사진 확대'),
                button: true,
                child: InkWell(
                  onTap: () => showDialog<void>(
                    context: context,
                    builder: (context) => Dialog(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Align(
                            alignment: Alignment.centerRight,
                            child: IconButton(
                              tooltip: AppStrings.tr(context, '사진 닫기'),
                              onPressed: () => Navigator.pop(context),
                              icon: const Icon(Icons.close),
                            ),
                          ),
                          MemoImageView(
                            memo: memo,
                            selected: selected,
                            height: MediaQuery.sizeOf(context).height * 0.65,
                            expandable: false,
                            zoomable: true,
                          ),
                        ],
                      ),
                    ),
                  ),
                  child: image,
                ),
              );
            },
          ),
    );
  }
}
