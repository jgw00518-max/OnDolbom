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
      return const Text('선택한 공간이 변경되었습니다.');
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
      return const Text('삭제된 메시지입니다.', style: TextStyle(color: Colors.grey));
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
                label: const Text('사진 다시 불러오기'),
              ),
            ),
            data: (bytes) {
              final image = Image.memory(
                bytes,
                // 목록은 사진을 채워 표시하고 확대 화면에서는 원본 전체를 보여준다.
                fit: expanded ? BoxFit.contain : BoxFit.cover,
                cacheWidth: expanded ? null : 600,
                errorBuilder: (_, _, _) =>
                    const Center(child: Text('사진을 표시할 수 없어요.')),
              );
              if (expanded) return InteractiveViewer(maxScale: 5, child: image);
              return Semantics(
                label: '채팅 사진 확대',
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
                              tooltip: '사진 닫기',
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
