import 'dart:async';
import 'dart:convert';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:ondolbom/vm/auth/auth_vm.dart';
import 'package:ondolbom/vm/auth/user_profile_vm.dart';

class ActivityCounts {
  const ActivityCounts({
    this.invites = 0,
    this.notifications = 0,
    this.notices = 0,
    this.inquiries = 0,
  });
  final int invites, notifications, notices, inquiries;
  bool get hasNews => invites + notifications + notices + inquiries > 0;
  ActivityCounts merge(Map<String, dynamic> values) => ActivityCounts(
    invites: values['invites'] as int? ?? invites,
    notifications: values['notifications'] as int? ?? notifications,
    notices: values['notices'] as int? ?? notices,
    inquiries: values['inquiries'] as int? ?? inquiries,
  );
}

final activityProvider =
    NotifierProvider.autoDispose<ActivityVm, ActivityCounts>(ActivityVm.new);

/// 목록 전체를 앱에 내려받지 않고 서버에서 계산한 항목별 숫자만 갱신한다.
class ActivityVm extends Notifier<ActivityCounts> {
  int _generation = 0;
  bool _loading = false;
  bool _forcePending = false;
  String? _uid;
  @override
  ActivityCounts build() {
    final generation = ++_generation;
    _loading = false;
    _forcePending = false;
    _uid = ref.watch(authUserProvider).asData?.value?.uid;
    final registered = ref.watch(userProfileProvider).asData?.value != null;
    if (_uid != null && registered) {
      Future.microtask(() {
        if (ref.mounted && generation == _generation) refresh(force: true);
      });
      final observer = _ActivityObserver(() => refresh(force: true));
      WidgetsBinding.instance.addObserver(observer);
      // 푸시·사용자 동작을 우선하고 놓친 변경만 5분마다 보완한다.
      final timer = Timer.periodic(const Duration(minutes: 5), (_) {
        if (WidgetsBinding.instance.lifecycleState == null ||
            WidgetsBinding.instance.lifecycleState ==
                AppLifecycleState.resumed) {
          refresh();
        }
      });
      ref.onDispose(() {
        timer.cancel();
        WidgetsBinding.instance.removeObserver(observer);
      });
    }
    // 이전 계정의 숫자는 계정 전환과 동시에 폐기한다.
    return const ActivityCounts();
  }

  Future<Map<String, dynamic>> _request(String path, {String? token}) async {
    final uid = _uid;
    final auth = ref.read(firebaseAuthProvider);
    final user = auth.currentUser;
    if (uid == null || user?.uid != uid) throw StateError('계정이 변경되었습니다.');
    final idToken = await user!.getIdToken().timeout(
      const Duration(seconds: 10),
    );
    if (!ref.mounted ||
        auth.currentUser?.uid != uid ||
        _uid != uid ||
        idToken == null) {
      throw StateError('계정이 변경되었습니다.');
    }
    final base = ref.read(apiBaseUrlProvider).replaceAll(RegExp(r'/+$'), '');
    final client = ref.read(authHttpClientProvider);
    final uri = Uri.parse('$base/activity$path');
    final headers = {
      'Authorization': 'Bearer $idToken',
      'Content-Type': 'application/json',
    };
    final response =
        await (token == null
                ? client.get(uri, headers: headers)
                : client.post(
                    uri,
                    headers: headers,
                    body: jsonEncode({'token': token}),
                  ))
            .timeout(const Duration(seconds: 20));
    if (!ref.mounted ||
        auth.currentUser?.uid != uid ||
        _uid != uid ||
        response.statusCode != 200) {
      throw StateError('새 소식 응답을 확인하지 못했습니다.');
    }
    return jsonDecode(utf8.decode(response.bodyBytes)) as Map<String, dynamic>;
  }

  // 일반 조회는 캐시를 사용하고 푸시·명시적 조작은 최신 값을 요청한다.
  Future<void> refresh({bool force = false}) async {
    if (_uid == null) return;
    if (_loading) {
      _forcePending |= force;
      return;
    }
    _loading = true;
    final generation = _generation;
    try {
      final result = await _request(force ? '/badges?force=true' : '/badges');
      if (ref.mounted && generation == _generation) state = state.merge(result);
    } catch (_) {
      // 일시적 장애를 0건으로 취급하지 않고 마지막 확인 숫자를 유지한다.
    } finally {
      if (ref.mounted && generation == _generation) {
        _loading = false;
        // 조회 중 들어온 푸시를 놓치지 않도록 최신 조회를 한 번 더 예약한다.
        if (_forcePending) {
          _forcePending = false;
          unawaited(refresh(force: true));
        }
      }
    }
  }

  Future<void> markRead(String path, String token) async {
    final generation = _generation;
    await _request('$path/read', token: token);
    if (!ref.mounted || generation != _generation) return;
    // 조회가 진행 중이었다면 그 결과가 반영된 뒤 최신 읽음 상태를 다시 조회한다.
    while (_loading && ref.mounted && generation == _generation) {
      await Future<void>.delayed(const Duration(milliseconds: 50));
    }
    if (ref.mounted && generation == _generation) await refresh(force: true);
  }
}

class _ActivityObserver extends WidgetsBindingObserver {
  _ActivityObserver(this.refresh);
  final VoidCallback refresh;
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) refresh();
  }
}
