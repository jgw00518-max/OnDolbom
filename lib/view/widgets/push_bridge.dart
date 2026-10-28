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
  StreamSubscription<void>? _received;
  PushEvent? _pending;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    final service = ref.read(pushServiceProvider);
    if (service != null) {
      _taps = service.taps.stream.listen((event) {
        if (mounted) setState(() => _pending = event);
      });
      _received = service.received.stream.listen((_) {
        if (!mounted) return;
        if (ref.exists(activityProvider)) {
          ref.read(activityProvider.notifier).refresh();
        }
        ref.invalidate(notificationsVmProvider);
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
      ref.read(pushServiceProvider)?.reconnect();
      if (ref.exists(notificationsVmProvider)) {
        ref.invalidate(notificationsVmProvider);
      }
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _taps?.cancel();
    _received?.cancel();
    super.dispose();
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
        _pending = null;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted ||
              ref.read(authUserProvider).asData?.value?.uid != target) {
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
