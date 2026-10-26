import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:ondolbom/model/chats/chat_message.dart';
import 'package:ondolbom/vm/chats/chat_vm.dart';
import 'package:ondolbom/vm/family_room/family_context.dart';

class ChatView extends ConsumerStatefulWidget {
  const ChatView({super.key});
  @override
  ConsumerState<ChatView> createState() => _ChatViewState();
}

class _ChatViewState extends ConsumerState<ChatView>
    with WidgetsBindingObserver {
  final _input = TextEditingController();
  final _scroll = ScrollController();
  FamilyContext? _selected;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _input.dispose();
    _scroll.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState lifecycle) {
    final selected = _selected;
    if (selected == null ||
        selected.userId.isEmpty ||
        selected.familyRoomId.isEmpty) {
      return;
    }
    final vm = ref.read(chatVmProvider(selected).notifier);
    if (lifecycle == AppLifecycleState.resumed) {
      vm.reconnect();
    } else if (lifecycle == AppLifecycleState.paused ||
        lifecycle == AppLifecycleState.detached) {
      vm.pause();
    }
  }

  void _send(ChatVm vm) {
    if (!vm.send(_input.text)) return;
    _input.clear();
    if (_scroll.hasClients) _scroll.jumpTo(0);
  }

  @override
  Widget build(BuildContext context) {
    final selected = ref.watch(familyContextProvider);
    if (_selected != selected) {
      _input.clear();
      _selected = selected;
    }
    if (selected.userId.isEmpty || selected.familyRoomId.isEmpty) {
      return Scaffold(
        appBar: AppBar(title: const Text('가족 채팅')),
        body: const Center(child: Text('로그인 후 가족 공간을 선택해 주세요.')),
      );
    }
    final provider = chatVmProvider(selected);
    final state = ref.watch(provider);
    final vm = ref.read(provider.notifier);
    final colors = Theme.of(context).colorScheme;
    final label = switch (state.status) {
      ChatStatus.connecting => '연결 중…',
      ChatStatus.connected => '연결됨',
      ChatStatus.reconnecting => '다시 연결 중…',
      ChatStatus.offline => '연결 끊김',
      ChatStatus.blocked => '연결할 수 없음',
    };
    // 새 메시지는 화면 하단에 추가한다. 과거 대화 조회 중에는 스크롤을 강제로 내리지 않는다.
    final messages = state.messages.reversed.toList();
    final pending = state.pending.reversed.toList();
    return Scaffold(
      appBar: AppBar(title: const Text('가족 채팅')),
      body: SafeArea(
        top: false,
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 720),
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 8,
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.home_outlined, size: 18),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          selected.roomName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(label, style: TextStyle(color: colors.primary)),
                    ],
                  ),
                ),
                if (state.error != null || state.status != ChatStatus.connected)
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            state.error ?? '가족 채팅에 연결하고 있습니다.',
                            style: TextStyle(color: colors.error),
                          ),
                        ),
                        TextButton(
                          onPressed: state.status == ChatStatus.connecting
                              ? null
                              : vm.reconnect,
                          child: const Text('다시 연결'),
                        ),
                      ],
                    ),
                  ),
                const Divider(height: 1),
                Expanded(
                  child:
                      state.loadingHistory &&
                          messages.isEmpty &&
                          pending.isEmpty
                      ? const Center(child: CircularProgressIndicator())
                      : messages.isEmpty && pending.isEmpty
                      ? Center(
                          child: Text(
                            state.status == ChatStatus.connected
                                ? '아직 대화가 없어요. 가족에게 첫 메시지를 보내보세요.'
                                : '연결 후 대화를 확인할 수 있습니다.',
                          ),
                        )
                      : ListView.builder(
                          key: const ValueKey('chat-messages'),
                          controller: _scroll,
                          reverse: true,
                          padding: const EdgeInsets.all(16),
                          itemCount:
                              pending.length +
                              messages.length +
                              (state.hasOlder ? 1 : 0),
                          itemBuilder: (context, index) {
                            if (index < pending.length) {
                              final message = pending[index];
                              return _Bubble(
                                key: ValueKey(message.id),
                                content: message.content,
                                mine: true,
                                footer: message.failed ? '전송 확인 실패' : '전송 중…',
                                retry: message.failed
                                    ? () => vm.retry(message.id)
                                    : null,
                                retryEnabled: state.canSend,
                              );
                            }
                            final messageIndex = index - pending.length;
                            if (messageIndex == messages.length) {
                              return TextButton(
                                onPressed: state.loadingOlder
                                    ? null
                                    : vm.loadOlder,
                                child: Text(
                                  state.loadingOlder ? '불러오는 중…' : '이전 대화 더 보기',
                                ),
                              );
                            }
                            final message = messages[messageIndex];
                            return _Bubble(
                              key: ValueKey('chat-${message.seq}'),
                              content: message.content,
                              mine: message.userId == selected.userId,
                              author: message.authorLabel,
                              footer: _time(message),
                            );
                          },
                        ),
                ),
                const Divider(height: 1),
                Padding(
                  padding: const EdgeInsets.all(12),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Expanded(
                        child: TextField(
                          key: const ValueKey('chat-input'),
                          controller: _input,
                          minLines: 1,
                          maxLines: 4,
                          maxLength: 4000,
                          textInputAction: TextInputAction.newline,
                          decoration: const InputDecoration(
                            hintText: '가족에게 메시지를 보내세요',
                            border: OutlineInputBorder(),
                            counterText: '',
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      ValueListenableBuilder<TextEditingValue>(
                        valueListenable: _input,
                        builder: (context, value, _) => IconButton.filled(
                          tooltip: '메시지 전송',
                          onPressed:
                              state.canSend && value.text.trim().isNotEmpty
                              ? () => _send(vm)
                              : null,
                          icon: const Icon(Icons.send),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  String _time(ChatMessage message) {
    final value = message.sentAt;
    if (value == null) return '저장됨';
    return '${value.month}/${value.day} ${value.hour.toString().padLeft(2, '0')}:${value.minute.toString().padLeft(2, '0')}';
  }
}

class _Bubble extends StatelessWidget {
  const _Bubble({
    super.key,
    required this.content,
    required this.mine,
    required this.footer,
    this.author = '나',
    this.retry,
    this.retryEnabled = false,
  });
  final String content;
  final String author;
  final bool mine;
  final String footer;
  final VoidCallback? retry;
  final bool retryEnabled;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Align(
      alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        constraints: const BoxConstraints(maxWidth: 420),
        margin: EdgeInsets.only(
          bottom: 12,
          left: mine ? 40 : 0,
          right: mine ? 0 : 40,
        ),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: mine ? colors.secondaryContainer : Theme.of(context).cardColor,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: colors.outlineVariant),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              author,
              style: TextStyle(fontSize: 12, color: colors.onSurfaceVariant),
            ),
            const SizedBox(height: 4),
            SelectableText(content),
            const SizedBox(height: 6),
            Text(
              footer,
              style: TextStyle(fontSize: 11, color: colors.onSurfaceVariant),
            ),
            if (retry != null)
              TextButton(
                onPressed: retryEnabled ? retry : null,
                child: const Text('재전송'),
              ),
          ],
        ),
      ),
    );
  }
}
