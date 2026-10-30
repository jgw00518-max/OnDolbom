import 'package:ondolbom/l10n/app_strings.dart';
import 'package:ondolbom/theme/app_colors.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:ondolbom/vm/chats/chat_image_vm.dart';
import 'package:ondolbom/vm/chats/chat_vm.dart';
import 'package:ondolbom/vm/family_room/family_context.dart';

class ChatImageView extends ConsumerWidget {
  const ChatImageView({super.key, required this.query, this.expanded = false});
  final ChatImageQuery query;
  final bool expanded;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (ref.watch(familyContextProvider) != query.context) {
      return Text(AppStrings.tr(context, '선택한 공간이 변경되었습니다.'));
    }
    final deleted = ref.watch(
      chatVmProvider(query.context).select(
        (state) =>
            state.messages
                .where((item) => item.seq == query.seq)
                .firstOrNull
                ?.isDeleted ==
            true,
      ),
    );
    if (deleted) {
      return Text(
        AppStrings.tr(context, '삭제된 메시지입니다.'),
        style: TextStyle(color: AppColors.resolve(context, Colors.grey)),
      );
    }
    final provider = chatImageProvider(query);
    return SizedBox(
      width: expanded ? double.infinity : 260,
      height: expanded ? MediaQuery.sizeOf(context).height * 0.6 : 200,
      child: ref
          .watch(provider)
          .when(
            skipLoadingOnRefresh: false,
            skipLoadingOnReload: false,
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (_, _) => Center(
              child: TextButton.icon(
                onPressed: () => ref.invalidate(provider),
                icon: const Icon(Icons.refresh),
                label: Text(AppStrings.tr(context, '사진 다시 불러오기')),
              ),
            ),
            data: (bytes) {
              final image = Image.memory(
                bytes,
                // 목록은 사진을 채워 표시하고 확대 화면에서는 원본 전체를 보여준다.
                fit: expanded ? BoxFit.contain : BoxFit.cover,
                cacheWidth: expanded ? null : 600,
                errorBuilder: (_, _, _) => Center(
                  child: Text(AppStrings.tr(context, '사진을 표시할 수 없어요.')),
                ),
              );
              if (expanded) return InteractiveViewer(maxScale: 5, child: image);
              return Semantics(
                label: AppStrings.tr(context, '채팅 사진 확대'),
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
                          ChatImageView(query: query, expanded: true),
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
