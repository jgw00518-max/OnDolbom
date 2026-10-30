import 'package:ondolbom/view/widgets/app_empty_state.dart';
import 'package:ondolbom/l10n/app_strings.dart';
import 'package:ondolbom/view/widgets/menu_header_icon.dart';
import 'dart:async';
import 'package:ondolbom/vm/chats/chat_notifications_vm.dart';
import 'package:ondolbom/view/widgets/app_back_button.dart';
import 'dart:typed_data';
import 'package:ondolbom/theme/app_colors.dart';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:ondolbom/model/chats/chat_message.dart';
import 'package:ondolbom/vm/chats/chat_vm.dart';
import 'package:ondolbom/vm/chats/chat_image_vm.dart';
import 'package:ondolbom/view/chats/chat_image_view.dart';
import 'package:ondolbom/view/chats/chat_edit_dialog.dart';
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
  Uint8List? _image;
  bool _picking = false;
  bool _actionsOpen = false;
  Timer? _readTimer;
  bool _reading = false;
  bool _readFailed = false;
  int _readThrough = -1;
  ModalRoute<dynamic>? _route;
  late ChatVisibility _visibility;

  bool _isVisible(String roomId, int seq) {
    final selected = _selected;
    if (!mounted ||
        selected == null ||
        selected.familyRoomId != roomId ||
        _route?.isCurrent != true ||
        (WidgetsBinding.instance.lifecycleState != null &&
            WidgetsBinding.instance.lifecycleState !=
                AppLifecycleState.resumed) ||
        ref.read(familyContextProvider) != selected) {
      return false;
    }
    if (seq == 0) return true;
    final state = ref.read(chatVmProvider(selected));
    return !state.loadingHistory &&
        state.messages.any((message) => message.seq >= seq);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _route = ModalRoute.of(context);
    final selected = _selected;
    if (selected != null) {
      _scheduleRead(ref.read(chatVmProvider(selected)), selected);
    }
  }

  // 실제 열린 채팅 화면에 반영된 번호까지만 300ms 단위로 묶어 읽음 처리한다.
  void _scheduleRead(ChatState state, FamilyContext selected) {
    if (_readFailed ||
        state.loadingHistory ||
        state.status == ChatStatus.blocked ||
        !_isVisible(selected.familyRoomId, 0)) {
      return;
    }
    final seq = state.messages.fold<int>(
      0,
      (value, item) => item.seq > value ? item.seq : value,
    );
    if (seq <= _readThrough || _reading) return;
    _readTimer?.cancel();
    _readTimer = Timer(const Duration(milliseconds: 300), () async {
      if (!mounted ||
          _selected != selected ||
          !_isVisible(selected.familyRoomId, 0)) {
        return;
      }
      _reading = true;
      try {
        final read = await ref
            .read(chatNotificationsApiProvider)
            .markRead(selected.familyRoomId, seq);
        if (!mounted || _selected != selected) return;
        _readThrough = read > _readThrough ? read : _readThrough;
        if (_readFailed) setState(() => _readFailed = false);
        ref.invalidate(chatUnreadProvider);
      } catch (_) {
        if (mounted && _selected == selected) {
          setState(() => _readFailed = true);
        }
      } finally {
        _reading = false;
        if (mounted && _selected != null && !_readFailed) {
          final current = _selected!;
          _scheduleRead(ref.read(chatVmProvider(current)), current);
        }
      }
    });
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _visibility = ref.read(chatVisibilityProvider);
    _visibility.register(this, _isVisible);
  }

  @override
  void dispose() {
    _readTimer?.cancel();
    _visibility.unregister(this);
    WidgetsBinding.instance.removeObserver(this);
    _input.dispose();
    _scroll.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState lifecycle) {
    if (_picking) return;
    final selected = _selected;
    if (selected == null ||
        selected.userId.isEmpty ||
        selected.familyRoomId.isEmpty) {
      return;
    }
    final vm = ref.read(chatVmProvider(selected).notifier);
    if (lifecycle == AppLifecycleState.resumed) {
      vm.reconnect();
      _scheduleRead(ref.read(chatVmProvider(selected)), selected);
    } else if (lifecycle == AppLifecycleState.paused ||
        lifecycle == AppLifecycleState.detached) {
      vm.pause();
    }
  }

  void _send(ChatVm vm) {
    if (!vm.send(_input.text, image: _image)) return;
    _input.clear();
    setState(() => _image = null);
    if (_scroll.hasClients) _scroll.jumpTo(0);
  }

  Future<void> _pickImage(FamilyContext selected) async {
    if (_picking) return;
    setState(() => _picking = true);
    try {
      final bytes = await ref.read(chatImagePickerProvider)();
      if (!mounted ||
          ref.read(familyContextProvider) != selected ||
          bytes == null) {
        return;
      }
      if (bytes.isEmpty || bytes.length > maxChatImageBytes) {
        throw const ChatFailure('이미지는 비어 있지 않은 5MB 이하 파일로 첨부해 주세요.');
      }
      setState(() => _image = bytes);
    } catch (error) {
      if (!mounted || ref.read(familyContextProvider) != selected) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            AppStrings.error(
              context,
              error is ChatFailure
                  ? error.message
                  : AppStrings.tr(context, '사진을 선택하지 못했어요. 사진 접근 권한을 확인해 주세요.'),
            ),
          ),
        ),
      );
    } finally {
      if (mounted) setState(() => _picking = false);
    }
  }

  Future<void> _messageActions(
    FamilyContext selected,
    ChatMessage message,
  ) async {
    if (_actionsOpen) return;
    _actionsOpen = true;
    try {
      final action = await showModalBottomSheet<String>(
        context: context,
        builder: (context) => SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(Icons.edit_outlined),
                title: Text(AppStrings.tr(context, '수정')),
                onTap: () => Navigator.pop(context, 'edit'),
              ),
              ListTile(
                leading: const Icon(Icons.delete_outline),
                title: Text(AppStrings.tr(context, '삭제')),
                onTap: () => Navigator.pop(context, 'delete'),
              ),
            ],
          ),
        ),
      );
      if (!mounted ||
          action == null ||
          ref.read(familyContextProvider) != selected) {
        return;
      }
      final state = ref.read(chatVmProvider(selected));
      final current = state.messages
          .where((item) => item.seq == message.seq)
          .firstOrNull;
      if (current == null ||
          current.isDeleted ||
          current.userId != selected.userId ||
          state.status != ChatStatus.connected ||
          state.loadingHistory ||
          state.changing.contains(current.seq)) {
        return;
      }
      if (action == 'edit') {
        await showDialog<void>(
          context: context,
          barrierDismissible: false,
          builder: (_) => ChatEditDialog(selected: selected, message: current),
        );
      } else {
        final approved = await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: Text(AppStrings.tr(context, '메시지 삭제')),
            content: Text(
              AppStrings.tr(context, '이 메시지를 삭제하시겠습니까?\n첨부 사진도 함께 숨겨집니다.'),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: Text(AppStrings.tr(context, '취소')),
              ),
              TextButton(
                onPressed: () => Navigator.pop(context, true),
                child: Text(AppStrings.tr(context, '삭제')),
              ),
            ],
          ),
        );
        if (!mounted ||
            approved != true ||
            ref.read(familyContextProvider) != selected) {
          return;
        }
        await ref
            .read(chatVmProvider(selected).notifier)
            .deleteMessage(current);
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              AppStrings.error(
                context,
                error is ChatFailure
                    ? error.message
                    : AppStrings.tr(context, '메시지를 변경하지 못했어요. 다시 시도해 주세요.'),
              ),
            ),
          ),
        );
      }
    } finally {
      _actionsOpen = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final selected = ref.watch(familyContextProvider);
    if (_selected != selected) {
      _input.clear();
      _image = null;
      _readTimer?.cancel();
      _readThrough = -1;
      _readFailed = false;
      _selected = selected;
    }
    if (selected.userId.isEmpty || selected.familyRoomId.isEmpty) {
      return Scaffold(
        appBar: AppBar(
          leadingWidth: 62,
          leading: const AppBackLeading(),
          title: Text(AppStrings.tr(context, '가족 채팅')),
          actions: const [MenuHeaderIcon(icon: Icons.chat_bubble_outline)],
        ),
        body: Center(
          child: Text(AppStrings.tr(context, '로그인 후 돌봄 공간을 선택해 주세요.')),
        ),
      );
    }
    final provider = chatVmProvider(selected);
    final state = ref.watch(provider);
    ref.listen(provider, (_, next) => _scheduleRead(next, selected));
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _selected == selected) _scheduleRead(state, selected);
    });
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
      appBar: AppBar(
        leadingWidth: 62,
        leading: const AppBackLeading(),
        title: Text(AppStrings.tr(context, '가족 채팅')),
        actions: const [MenuHeaderIcon(icon: Icons.chat_bubble_outline)],
      ),
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
                  // 상태 행이 내용 너비로 줄어들지 않게 화면 너비를 확보한다.
                  child: SizedBox(
                    width: double.infinity,
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        Icon(
                          Icons.circle,
                          size: 8,
                          color: state.status == ChatStatus.connected
                              ? AppColors.of(context).sageDark
                              : AppColors.of(context).textSecondary,
                        ),
                        const SizedBox(width: 5),
                        Flexible(
                          fit: FlexFit.loose,
                          child: Text(
                            AppStrings.tr(context, label),
                            textAlign: TextAlign.right,
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: state.status == ChatStatus.connected
                                  ? AppColors.of(context).sageDark
                                  : AppColors.of(context).textSecondary,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                if (state.error != null || state.status != ChatStatus.connected)
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            AppStrings.error(
                              context,
                              state.error ??
                                  AppStrings.tr(context, '가족 채팅에 연결하고 있습니다.'),
                            ),
                            style: TextStyle(color: colors.error),
                          ),
                        ),
                        TextButton(
                          onPressed: state.status == ChatStatus.connecting
                              ? null
                              : vm.reconnect,
                          child: Text(AppStrings.tr(context, '다시 연결')),
                        ),
                      ],
                    ),
                  ),
                if (_readFailed)
                  TextButton.icon(
                    onPressed: () {
                      setState(() => _readFailed = false);
                      _scheduleRead(state, selected);
                    },
                    icon: const Icon(Icons.refresh, size: 18),
                    label: Text(AppStrings.tr(context, '읽음 처리 실패 · 다시 시도')),
                  ),
                const Divider(height: 1),
                Expanded(
                  child:
                      state.loadingHistory &&
                          messages.isEmpty &&
                          pending.isEmpty
                      ? const Center(child: CircularProgressIndicator())
                      : messages.isEmpty && pending.isEmpty
                      ? AppEmptyState(
                          icon: Icons.chat_bubble_outline,
                          title: state.status == ChatStatus.connected
                              ? '아직 대화가 없어요'
                              : '연결 후 대화를 확인할 수 있습니다.',
                          description: state.status == ChatStatus.connected
                              ? '가족에게 첫 메시지를 보내보세요.'
                              : '연결 상태를 확인한 뒤 다시 시도해 주세요.',
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
                                image: message.image == null
                                    ? null
                                    : Stack(
                                        children: [
                                          Image.memory(
                                            message.image!,
                                            width: 260,
                                            height: 200,
                                            fit: BoxFit.contain,
                                            cacheWidth: 600,
                                            errorBuilder: (_, _, _) => Text(
                                              AppStrings.tr(
                                                context,
                                                '사진을 표시할 수 없어요.',
                                              ),
                                            ),
                                          ),
                                          if (!message.failed)
                                            const Positioned(
                                              right: 8,
                                              bottom: 8,
                                              child: SizedBox(
                                                width: 20,
                                                height: 20,
                                                child:
                                                    CircularProgressIndicator(
                                                      strokeWidth: 2,
                                                    ),
                                              ),
                                            ),
                                        ],
                                      ),
                              );
                            }
                            final messageIndex = index - pending.length;
                            if (messageIndex == messages.length) {
                              return TextButton(
                                onPressed: state.loadingOlder
                                    ? null
                                    : vm.loadOlder,
                                child: Text(
                                  state.loadingOlder
                                      ? AppStrings.tr(context, '불러오는 중…')
                                      : AppStrings.tr(context, '이전 대화 더 보기'),
                                ),
                              );
                            }
                            final message = messages[messageIndex];
                            final day = message.sentAt;
                            final olderDay = messageIndex + 1 < messages.length
                                ? messages[messageIndex + 1].sentAt
                                : null;
                            // 역순 목록의 더 오래된 메시지와 비교해 이전 대화 조회 시 날짜 중복을 막는다.
                            final showDate =
                                day != null &&
                                !DateUtils.isSameDay(day, olderDay);
                            return Column(
                              key: ValueKey('chat-day-${message.seq}'),
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                if (showDate) _DateSeparator(date: day),
                                _Bubble(
                                  key: ValueKey('chat-${message.seq}'),
                                  content: message.content,
                                  isDeleted: message.isDeleted,
                                  mine: message.userId == selected.userId,
                                  author: message.userId == selected.userId
                                      ? '나'
                                      : message.authorLabel,
                                  footer: state.changing.contains(message.seq)
                                      ? '변경 중…'
                                      : '${_time(message)}${message.updatedAt != null && !message.isDeleted ? ' · 수정됨' : ''}',
                                  onLongPress:
                                      message.userId == selected.userId &&
                                          !message.isDeleted &&
                                          state.status ==
                                              ChatStatus.connected &&
                                          !state.loadingHistory &&
                                          !state.changing.contains(message.seq)
                                      ? () => _messageActions(selected, message)
                                      : null,
                                  image: message.hasImage && !message.isDeleted
                                      ? ChatImageView(
                                          query: (
                                            context: selected,
                                            seq: message.seq,
                                          ),
                                        )
                                      : null,
                                ),
                              ],
                            );
                          },
                        ),
                ),
                const Divider(height: 1),
                if (_image != null)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
                    child: Row(
                      children: [
                        Image.memory(
                          _image!,
                          width: 80,
                          height: 80,
                          fit: BoxFit.contain,
                          cacheWidth: 200,
                          errorBuilder: (_, _, _) =>
                              Text(AppStrings.tr(context, '사진을 표시할 수 없어요.')),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(AppStrings.tr(context, '첨부 사진 1장')),
                        ),
                        IconButton(
                          tooltip: AppStrings.tr(context, '첨부 사진 제거'),
                          onPressed: _picking
                              ? null
                              : () => setState(() => _image = null),
                          icon: const Icon(Icons.close),
                        ),
                      ],
                    ),
                  ),
                Padding(
                  padding: const EdgeInsets.all(12),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      IconButton(
                        tooltip: _image == null
                            ? AppStrings.tr(context, '사진 첨부')
                            : AppStrings.tr(context, '첨부 사진 변경'),
                        onPressed: state.canSend && !_picking
                            ? () => _pickImage(selected)
                            : null,
                        icon: const Icon(Icons.photo_outlined),
                        style: IconButton.styleFrom(
                          minimumSize: const Size(44, 48),
                          backgroundColor: AppColors.of(context).peachSoft,
                          foregroundColor: AppColors.of(context).sageDark,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: TextField(
                          key: const ValueKey('chat-input'),
                          controller: _input,
                          minLines: 1,
                          maxLines: 4,
                          maxLength: 4000,
                          style: TextStyle(
                            fontSize: 16,
                            color: AppColors.of(context).textPrimary,
                          ),
                          textInputAction: TextInputAction.newline,
                          decoration: InputDecoration(
                            hintText: AppStrings.tr(context, '가족에게 메시지를 보내세요'),
                            filled: true,
                            fillColor: AppColors.of(context).surface,
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 14,
                              vertical: 14,
                            ),
                            hintStyle: TextStyle(
                              fontSize: 14,
                              color: AppColors.of(context).textSecondary,
                            ),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(16),
                              borderSide: BorderSide(
                                color: AppColors.of(context).border,
                              ),
                            ),
                            enabledBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(16),
                              borderSide: BorderSide(
                                color: AppColors.of(context).border,
                              ),
                            ),
                            focusedBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(16),
                              borderSide: BorderSide(
                                color: AppColors.of(context).sageDark,
                              ),
                            ),
                            counterText: '',
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      ValueListenableBuilder<TextEditingValue>(
                        valueListenable: _input,
                        builder: (context, value, _) => IconButton.filled(
                          style: IconButton.styleFrom(
                            minimumSize: const Size(48, 48),
                            backgroundColor: AppColors.of(context).sageDark,
                            foregroundColor: AppColors.of(context).surface,
                            disabledBackgroundColor: AppColors.of(
                              context,
                            ).sageLight,
                            disabledForegroundColor: AppColors.of(
                              context,
                            ).sageDark,
                          ),
                          tooltip: AppStrings.tr(context, '메시지 전송'),
                          onPressed:
                              state.canSend &&
                                  !_picking &&
                                  (value.text.trim().isNotEmpty ||
                                      _image != null)
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
    return '${value.hour < 12 ? '오전' : '오후'} ${value.hour % 12 == 0 ? 12 : value.hour % 12}:${value.minute.toString().padLeft(2, '0')}';
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
    this.image,
    this.onLongPress,
    this.isDeleted = false,
  });
  final String content;
  final String author;
  final bool mine;
  final String footer;
  final VoidCallback? retry;
  final bool retryEnabled;
  final Widget? image;
  final VoidCallback? onLongPress;
  final bool isDeleted;

  @override
  Widget build(BuildContext context) {
    final messageStyle = TextStyle(
      fontSize: 16,
      height: 1.5,
      color: AppColors.of(context).textPrimary,
    );
    return LayoutBuilder(
      builder: (context, constraints) => Align(
        alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
        child: Padding(
          padding: const EdgeInsets.only(bottom: 20),
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxWidth: constraints.maxWidth * (mine ? 0.86 : 0.92),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (!mine) ...[
                  ExcludeSemantics(
                    child: CircleAvatar(
                      radius: 17,
                      backgroundColor: AppColors.of(context).sageLight,
                      foregroundColor: AppColors.of(context).sageDark,
                      child: Text(
                        author.characters.first,
                        style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                ],
                Flexible(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: mine
                        ? CrossAxisAlignment.end
                        : CrossAxisAlignment.start,
                    children: [
                      if (!mine)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 6),
                          child: Text(
                            author,
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w700,
                              color: AppColors.of(context).textPrimary,
                            ),
                          ),
                        ),
                      if (onLongPress != null)
                        SizedBox(
                          height: 36,
                          child: IconButton(
                            tooltip: AppStrings.tr(context, '메시지 메뉴'),
                            onPressed: onLongPress,
                            padding: EdgeInsets.zero,
                            icon: Icon(
                              Icons.more_horiz,
                              size: 21,
                              color: AppColors.of(context).textSecondary,
                            ),
                          ),
                        ),
                      GestureDetector(
                        onLongPress: onLongPress,
                        behavior: HitTestBehavior.opaque,
                        child: Container(
                          constraints: const BoxConstraints(maxWidth: 420),
                          padding: EdgeInsets.all(image == null ? 14 : 8),
                          decoration: BoxDecoration(
                            color: mine
                                ? AppColors.of(context).peachSoft
                                : AppColors.of(context).surface,
                            borderRadius: BorderRadius.circular(18),
                            border: Border.all(
                              color: AppColors.of(context).border,
                            ),
                          ),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              if (image != null)
                                ClipRRect(
                                  borderRadius: BorderRadius.circular(12),
                                  child: image,
                                ),
                              if (image != null && content.isNotEmpty)
                                const SizedBox(height: 8),
                              if (content.isNotEmpty)
                                Padding(
                                  padding: EdgeInsets.all(
                                    image == null ? 0 : 4,
                                  ),
                                  child: onLongPress == null
                                      ? SelectableText(
                                          content,
                                          style: isDeleted
                                              ? messageStyle.copyWith(
                                                  color: AppColors.of(
                                                    context,
                                                  ).textSecondary,
                                                )
                                              : messageStyle,
                                        )
                                      : Text(content, style: messageStyle),
                                ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 5),
                      Text(
                        footer,
                        style: TextStyle(
                          fontSize: 12,
                          height: 1.4,
                          color: retry == null
                              ? AppColors.of(context).textSecondary
                              : Theme.of(context).colorScheme.error,
                        ),
                      ),
                      if (retry != null)
                        TextButton(
                          onPressed: retryEnabled ? retry : null,
                          child: Text(AppStrings.tr(context, '재전송')),
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
}

class _DateSeparator extends StatelessWidget {
  const _DateSeparator({required this.date});
  final DateTime date;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 12, bottom: 24),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: AppColors.of(context).peachSoft,
          borderRadius: BorderRadius.circular(24),
        ),
        child: Text(
          AppStrings.fullDate(context, date),
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: AppColors.of(context).sageDark,
          ),
        ),
      ),
    );
  }
}
