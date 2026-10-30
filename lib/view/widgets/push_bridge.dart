import 'package:ondolbom/vm/chats/chat_notifications_vm.dart';
import 'package:ondolbom/vm/chats/chat_vm.dart';
import 'package:ondolbom/vm/family_room/family_context.dart';
import 'package:ondolbom/vm/family_room/family_room_notifier.dart';
import 'package:ondolbom/view/chats/chat_view.dart';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:ondolbom/model/notifications/push_service.dart';
import 'package:ondolbom/view/notifications/notifications_view.dart';
import 'package:ondolbom/vm/auth/auth_vm.dart';
import 'package:ondolbom/vm/auth/user_profile_vm.dart';
import 'package:ondolbom/vm/activity/activity_vm.dart';
import 'package:ondolbom/vm/notifications/notifications_vm.dart';

/// 인증·프로필이 준비된 다음에만 기기를 등록하고 알림 화면으로 이동한다.
class PushBridge extends ConsumerStatefulWidget {
  const PushBridge({
    super.key,
    required this.navigatorKey,
    required this.child,
  });
  final GlobalKey<NavigatorState> navigatorKey;
  final Widget child;
  @override
  ConsumerState<PushBridge> createState() => _PushBridgeState();
}

class _PushBridgeState extends ConsumerState<PushBridge>
    with WidgetsBindingObserver {
  StreamSubscription<PushEvent>? _taps;
  StreamSubscription<PushEvent>? _received;
  Timer? _chatPoll;
  PushService? _service;
  PushEvent? _pending;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _chatPoll = Timer.periodic(const Duration(minutes: 5), (_) {
      if (mounted &&
          WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed) {
        ref.invalidate(chatUnreadProvider);
      }
    });
    final service = ref.read(pushServiceProvider);
    _service = service;
    if (service != null) {
      service.suppressForeground = (event) =>
          event.data['type'] == 'chat_message' &&
          ref
              .read(chatVisibilityProvider)
              .isVisible(
                event.data['family_room_id']?.toString() ?? '',
                int.tryParse(event.data['chat_seq']?.toString() ?? '') ?? -1,
              );
      _taps = service.taps.stream.listen((event) {
        if (mounted) setState(() => _pending = event);
      });
      // 앱 실행 중 푸시를 수신하면 배지와 알림 목록을 즉시 갱신한다.
      _received = service.received.stream.listen((event) {
        if (!mounted) return;
        if (event.data['type'] == 'chat_message') {
          // 채팅 수신으로 일정 알림 전체를 다시 읽지 않는다.
          ref.invalidate(chatUnreadProvider);
          return;
        }
        if (ref.exists(activityProvider)) {
          ref.read(activityProvider.notifier).refresh(force: true);
        }
        ref.invalidate(notificationsVmProvider);
        if (event.data['type'] == 'family_room_deleted') {
          // 삭제된 공간이 선택 목록에 남지 않도록 최신 공간 목록도 갱신한다.
          unawaited(ref.read(familyRoomProvider.notifier).fetchRooms());
        }
      });
      unawaited(
        service.start().catchError((Object _) {
          service.status.value = '푸시 초기화 실패 · 다시 연결해 주세요.';
        }),
      );
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      // 앱 복귀 시 기기 연결의 유효 기간과 계정 연결을 갱신한다.
      ref.read(pushServiceProvider)?.reconnect();
      ref.invalidate(chatUnreadProvider);
      if (ref.exists(notificationsVmProvider)) {
        ref.invalidate(notificationsVmProvider);
      }
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _chatPoll?.cancel();
    _service?.suppressForeground = null;
    _taps?.cancel();
    _received?.cancel();
    super.dispose();
  }

  Future<void> _openChat(PushEvent event, String uid) async {
    final roomId = event.data['family_room_id']?.toString();
    if (roomId == null || roomId.isEmpty) return;
    try {
      final notifier = ref.read(familyRoomProvider.notifier);
      // 이미 진행 중인 공간 조회가 있다면 끝난 뒤 최신 권한으로 다시 조회한다.
      for (
        var wait = 0;
        ref.read(familyRoomProvider).isLoading && wait < 100;
        wait++
      ) {
        await Future<void>.delayed(const Duration(milliseconds: 50));
        if (!mounted ||
            ref.read(authUserProvider).asData?.value?.uid != uid ||
            _service?.auth.currentUser?.uid != uid) {
          return;
        }
      }
      await notifier.fetchRooms();
      if (!mounted ||
          ref.read(authUserProvider).asData?.value?.uid != uid ||
          _service?.auth.currentUser?.uid != uid) {
        return;
      }
      final state = ref.read(familyRoomProvider);
      if (state.errorMessage != null ||
          state.participations[roomId]?.isActive != true ||
          !state.rooms.any((room) => room.familyRoomId == roomId)) {
        throw const ChatFailure(
          '현재 참여 중인 채팅 공간을 확인하지 못했습니다. 공간 목록을 새로고침해 주세요.',
        );
      }
      notifier.selectRoom(roomId);
      ref.invalidate(chatUnreadProvider);
      if (ref.read(chatVisibilityProvider).isVisible(roomId, 0)) {
        ref.invalidate(chatVmProvider(ref.read(familyContextProvider)));
      } else {
        widget.navigatorKey.currentState?.push(
          MaterialPageRoute<void>(builder: (_) => const ChatView()),
        );
      }
    } catch (_) {
      if (!mounted) return;
      final context = widget.navigatorKey.currentContext;
      if (context != null && context.mounted) {
        ScaffoldMessenger.maybeOf(context)?.showSnackBar(
          const SnackBar(
            content: Text('채팅 공간에 접근할 수 없습니다. 공간 목록과 참여 상태를 확인해 주세요.'),
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final service = ref.watch(pushServiceProvider);
    if (service != null) {
      final user = ref.watch(authUserProvider).asData?.value;
      final profile = ref.watch(userProfileProvider).asData?.value;
      scheduleMicrotask(() {
        if (mounted) service.setSession(user?.uid, profile != null);
      });
      final target = _pending?.data['user_uid'];
      if (user != null && target != null && user.uid != target) _pending = null;
      if (_pending != null &&
          user != null &&
          profile != null &&
          target == user.uid) {
        final event = _pending!;
        _pending = null;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted ||
              ref.read(authUserProvider).asData?.value?.uid != target) {
            return;
          }
          if (event.data['type'] == 'chat_message') {
            unawaited(_openChat(event, target));
            return;
          }
          ref.invalidate(notificationsVmProvider);
          widget.navigatorKey.currentState?.push(
            MaterialPageRoute<void>(builder: (_) => const NotificationsView()),
          );
        });
      }
    }
    return widget.child;
  }
}

class PushSettingsTile extends ConsumerWidget {
  const PushSettingsTile({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final service = ref.watch(pushServiceProvider);
    if (service == null) return const SizedBox.shrink();
    return ValueListenableBuilder<String>(
      valueListenable: service.status,
      builder: (context, status, _) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ListTile(
            leading: const Icon(Icons.notifications_outlined),
            title: const Text('기기 푸시 알림'),
            subtitle: Text(status),
          ),
          Wrap(
            children: [
              TextButton(
                onPressed: () => service.reconnect(),
                child: const Text('다시 연결'),
              ),
              TextButton(
                onPressed: () => service.sendTest(),
                child: const Text('테스트 알림 보내기'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
