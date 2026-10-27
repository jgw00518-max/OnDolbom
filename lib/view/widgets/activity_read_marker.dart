import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:ondolbom/vm/activity/activity_vm.dart';

/// 상세가 실제로 표시된 뒤 해당 버전만 읽음 처리한다. 새 답변까지 미리 지우지 않는다.
class ActivityReadMarker extends ConsumerStatefulWidget {
  const ActivityReadMarker({
    super.key,
    required this.path,
    required this.token,
    required this.child,
  });
  final String path;
  final String? token;
  final Widget child;
  @override
  ConsumerState<ActivityReadMarker> createState() => _ActivityReadMarkerState();
}

class _ActivityReadMarkerState extends ConsumerState<ActivityReadMarker> {
  bool _failed = false;
  @override
  void initState() {
    super.initState();
    _schedule();
  }

  @override
  void didUpdateWidget(covariant ActivityReadMarker oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.token != widget.token || oldWidget.path != widget.path) {
      _schedule();
    }
  }

  void _schedule() => WidgetsBinding.instance.addPostFrameCallback((_) {
    if (mounted) _mark();
  });
  Future<void> _mark() async {
    final token = widget.token;
    if (token == null) return;
    try {
      await ref.read(activityProvider.notifier).markRead(widget.path, token);
      if (mounted) setState(() => _failed = false);
    } catch (_) {
      if (mounted) setState(() => _failed = true);
    }
  }

  @override
  Widget build(BuildContext context) {
    ref.watch(activityProvider);
    return Column(
      children: [
        if (_failed)
          TextButton(
            onPressed: _mark,
            child: const Text('읽음 상태 저장 실패 · 다시 시도'),
          ),
        Expanded(child: widget.child),
      ],
    );
  }
}
