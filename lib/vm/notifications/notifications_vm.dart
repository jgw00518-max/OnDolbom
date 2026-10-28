import 'package:ondolbom/model/schedules/schedule.dart';
import 'package:ondolbom/vm/schedules/schedule_vm.dart';
import 'package:ondolbom/vm/activity/activity_vm.dart';
import 'dart:async';
import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:ondolbom/model/notifications/schedule_notification.dart';
import 'package:ondolbom/vm/auth/auth_vm.dart';
import 'package:ondolbom/vm/auth/user_profile_vm.dart';

class NotificationsError implements Exception {
  const NotificationsError(this.message);
  final String message;
  @override
  String toString() => message;
}

/// 화면 상태를 가진 VM에서 호출하는 요청 함수. 기존 인증·HTTP Provider를 공유한다.
Future<Map<String, dynamic>> _request(
  Ref ref,
  String path, {
  bool post = false,
}) async {
  final session = await ref.read(authUserProvider.future);
  if (session == null) throw const NotificationsError('다시 로그인해 주세요.');
  final auth = ref.read(firebaseAuthProvider);
  final client = ref.read(authHttpClientProvider);
  final base = ref.read(apiBaseUrlProvider).replaceAll(RegExp(r'/+$'), '');
  try {
    for (var attempt = 0; attempt < 2; attempt++) {
      final user = auth.currentUser;
      if (user == null || user.uid != session.uid) {
        throw const NotificationsError('로그인 계정이 변경되었습니다.');
      }
      final token = await user
          .getIdToken(attempt == 1)
          .timeout(const Duration(seconds: 10));
      if (token == null) throw const NotificationsError('다시 로그인해 주세요.');
      final headers = {
        'Authorization': 'Bearer $token',
        'Accept': 'application/json',
      };
      final uri = Uri.parse('$base$path');
      final response =
          await (post
                  ? client.post(uri, headers: headers)
                  : client.get(uri, headers: headers))
              .timeout(const Duration(seconds: 15));
      if (response.statusCode == 401 && attempt == 0) continue;
      if (response.statusCode != 200) {
        throw NotificationsError(switch (response.statusCode) {
          401 => '다시 로그인해 주세요.',
          403 => '등록된 가족 사용자만 이용할 수 있습니다.',
          404 => '일정이 삭제되었거나 현재 접근할 수 없습니다.',
          410 => '삭제된 일정입니다.',
          409 => '이미 변경된 요청입니다. 최신 일정을 확인해 주세요.',
          503 => 'Firestore 설정과 서버 연결을 확인해 주세요.',
          _ => '알림을 처리하지 못했습니다. 다시 시도해 주세요.',
        });
      }
      // 계정 전환 뒤 늦게 도착한 응답을 이전 계정 화면에 반영하지 않는다.
      if (auth.currentUser?.uid != session.uid) {
        throw const NotificationsError('로그인 계정이 변경되었습니다.');
      }
      return jsonDecode(utf8.decode(response.bodyBytes))
          as Map<String, dynamic>;
    }
    throw const NotificationsError('다시 로그인해 주세요.');
  } on NotificationsError {
    rethrow;
  } on TimeoutException {
    throw const NotificationsError('서버 응답 시간이 초과되었습니다. 다시 시도해 주세요.');
  } catch (_) {
    throw const NotificationsError('알림 서버 연결 또는 응답을 확인해 주세요.');
  }
}

class NotificationList {
  const NotificationList(this.items, this.nextBeforeId);
  final List<ScheduleNotification> items;
  final String? nextBeforeId;
}

final notificationsVmProvider =
    AsyncNotifierProvider.autoDispose<NotificationsVm, NotificationList>(
      NotificationsVm.new,
      retry: (_, _) => null,
    );

class NotificationsVm extends AsyncNotifier<NotificationList> {
  int _generation = 0;
  @override
  Future<NotificationList> build() async {
    _generation++;
    // 인증 사용자 변경 시 목록을 초기화한다. 읽음 갱신 중에도 HTTP 연결을 유지한다.
    ref.watch(authUserProvider);
    ref.watch(authHttpClientProvider);
    return _load();
  }

  Future<NotificationList> _load({String? before}) async {
    final body = await _request(
      ref,
      '/schedules/schedule-notifications?scope=v2${before == null ? '' : '&before_id=${Uri.encodeQueryComponent(before)}'}',
    );
    return NotificationList(
      (body['results'] as List)
          .map(
            (item) =>
                ScheduleNotification.fromJson(item as Map<String, dynamic>),
          )
          .toList(),
      body['next_before_id']?.toString(),
    );
  }

  bool _loadingMore = false;
  Future<void> loadMore() async {
    final previous = state.asData?.value;
    if (previous?.nextBeforeId == null || _loadingMore) return;
    _loadingMore = true;
    final generation = _generation;
    try {
      final page = await _load(before: previous!.nextBeforeId);
      if (ref.mounted && generation == _generation) {
        state = AsyncData(
          NotificationList([
            ...previous.items,
            ...page.items,
          ], page.nextBeforeId),
        );
      }
    } finally {
      _loadingMore = false;
    }
  }

  Future<({Schedule item, ScheduleQuery query})> detail(
    ScheduleNotification notification,
  ) async {
    final generation = _generation;
    final date = DateTime.parse(notification.date);
    final query = (
      familyRoomId: notification.spaceId,
      year: date.year,
      month: date.month,
    );
    final body = await _request(
      ref,
      '/schedules?family_room_id=${Uri.encodeQueryComponent(query.familyRoomId)}&year=${query.year}&month=${query.month}',
    );
    if (!ref.mounted || generation != _generation) {
      throw const NotificationsError('로그인 상태가 변경되었습니다.');
    }
    final items = (body['results'] as List).map(
      (row) => Schedule.fromJson(row as Map<String, dynamic>),
    );
    for (final item in items) {
      if (item.seq == notification.scheduleId) {
        return (item: item, query: query);
      }
    }
    throw const NotificationsError('일정이 변경되었거나 현재 조회할 수 없습니다. 알림을 다시 열어 주세요.');
  }

  Future<ScheduleNotification> open(
    String notificationId, {
    ScheduleNotification? deleted,
  }) async {
    final generation = _generation;
    // 진입 직전 서버 권한을 재검사한다. 알림의 과거 데이터를 그대로 상세로 넘기지 않는다.
    // 삭제 알림은 일반 일정 조회가 410이므로 안내와 읽음 처리를 분리한다.
    final body = deleted == null
        ? await _request(
            ref,
            '/schedules/schedule-notifications/${Uri.encodeComponent(notificationId)}/schedule',
          )
        : null;
    final receipt = await _request(
      ref,
      '/schedules/schedule-notifications/${Uri.encodeComponent(notificationId)}/read',
      post: true,
    );
    if (!ref.mounted || generation != _generation) {
      throw const NotificationsError('알림 목록이 변경되었습니다. 다시 열어 주세요.');
    }
    if (ref.mounted) {
      if (ref.exists(activityProvider)) {
        ref.read(activityProvider.notifier).refresh();
      }
      // 열기 요청 도중 provider를 재생성하지 않고 해당 항목의 읽음만 반영한다.
      final previous = state.asData?.value;
      if (previous != null) {
        state = AsyncData(
          NotificationList([
            for (final item in previous.items)
              item.id == notificationId
                  ? item.withReadAt(receipt['read_at'] as String?)
                  : item,
          ], previous.nextBeforeId),
        );
      }
    }
    return deleted ?? ScheduleNotification.fromJson(body!);
  }
}
