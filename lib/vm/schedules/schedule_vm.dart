import 'package:ondolbom/model/schedules/schedule.dart';
import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;

import 'package:ondolbom/vm/auth/auth_vm.dart';
import 'package:ondolbom/vm/auth/user_profile_vm.dart';

// 일정 API 요청에 사용할 클라이언트
final scheduleHttpClientProvider = Provider<http.Client>((ref) {
  final client = http.Client();

  ref.onDispose(client.close);

  return client;
});

// 화면에서 사용할 일정 VM
final scheduleVmProvider = Provider<ScheduleVm>((ref) {
  return ScheduleVm(ref);
});

typedef ScheduleQuery = ({String familyRoomId, int year, int month});

// 월·공간·로그인 상태별로 조회를 분리한다.
final scheduleListProvider = FutureProvider.autoDispose
    .family<List<Schedule>, ScheduleQuery>((ref, query) async {
      final user = await ref.watch(authUserProvider.future);
      if (user == null) throw Exception('로그인이 필요합니다.');
      return ref.read(scheduleVmProvider).fetchSchedules(query);
    }, retry: (retryCount, error) => null);

class ScheduleVm {
  ScheduleVm(this.ref);

  final Ref ref;

  // 일정을 등록하고 알림 발행 여부를 반환한다.
  Future<bool> createSchedule({
    required String familyRoomId,
    required String scheduleDate,
    required String startTime,
    required String endTime,
    required String name,
    required String memo,
  }) async {
    final auth = ref.read(firebaseAuthProvider);
    final user = auth.currentUser;

    if (user == null) {
      throw Exception('로그인이 필요합니다.');
    }

    final token = await user.getIdToken();

    if (!ref.mounted || auth.currentUser?.uid != user.uid) {
      throw Exception('로그인 상태가 변경되었습니다.');
    }

    if (token == null || token.isEmpty) {
      throw Exception('로그인 정보를 가져오지 못했습니다.');
    }

    final baseUrl = ref.read(apiBaseUrlProvider).replaceAll(RegExp(r'/+$'), '');

    final response = await ref
        .read(scheduleHttpClientProvider)
        .post(
          Uri.parse('$baseUrl/schedules'),
          headers: {
            'Content-Type': 'application/json; charset=utf-8',
            'Authorization': 'Bearer $token',
          },
          body: jsonEncode({
            'family_room_id': familyRoomId,
            'schedule_date': scheduleDate,
            'start_time': startTime,
            'end_time': endTime,
            'schedule_name': name.trim().isEmpty ? null : name.trim(),
            'schedule_memo': memo.trim().isEmpty ? null : memo.trim(),
          }),
        )
        .timeout(const Duration(seconds: 45));

    if (!ref.mounted || auth.currentUser?.uid != user.uid) {
      throw Exception('로그인 상태가 변경되었습니다.');
    }

    final body = jsonDecode(utf8.decode(response.bodyBytes));

    if (response.statusCode != 201) {
      final detail = body is Map ? body['detail'] : null;

      throw Exception(detail is String ? detail : '일정 입력 내용과 서버 상태를 확인해 주세요.');
    }

    return body['notification_published'] == true;
  }

  // 선택한 공간·월의 일정을 서버에서 조회한다.
  Future<List<Schedule>> fetchSchedules(ScheduleQuery query) async {
    final auth = ref.read(firebaseAuthProvider);
    final user = auth.currentUser;
    if (user == null) throw Exception('로그인이 필요합니다.');
    final token = await user.getIdToken();
    if (!ref.mounted || auth.currentUser?.uid != user.uid) {
      throw Exception('로그인 상태가 변경되었습니다.');
    }
    if (token == null || token.isEmpty) throw Exception('로그인 정보를 가져오지 못했습니다.');
    final baseUrl = ref.read(apiBaseUrlProvider).replaceAll(RegExp(r'/+$'), '');
    final uri = Uri.parse('$baseUrl/schedules').replace(
      queryParameters: {
        'family_room_id': query.familyRoomId,
        'year': '${query.year}',
        'month': '${query.month}',
      },
    );
    final response = await ref
        .read(scheduleHttpClientProvider)
        .get(uri, headers: {'Authorization': 'Bearer $token'})
        .timeout(const Duration(seconds: 15));
    if (!ref.mounted || auth.currentUser?.uid != user.uid) {
      throw Exception('로그인 상태가 변경되었습니다.');
    }
    final body = jsonDecode(utf8.decode(response.bodyBytes));
    if (response.statusCode != 200) {
      final detail = body is Map ? body['detail'] : null;
      throw Exception(detail is String ? detail : '일정 목록을 불러오지 못했습니다.');
    }
    return (body['results'] as List)
        .map((item) => Schedule.fromJson(item as Map<String, dynamic>))
        .toList();
  }

  // 로그인한 일반 가족이 일정을 수락한다.
  Future<void> acceptSchedule(int scheduleSeq) async {
    final auth = ref.read(firebaseAuthProvider);
    final user = auth.currentUser;
    if (user == null) throw Exception('로그인이 필요합니다.');
    final token = await user.getIdToken();
    if (!ref.mounted || auth.currentUser?.uid != user.uid) {
      throw Exception('로그인 상태가 변경되었습니다.');
    }
    if (token == null || token.isEmpty) {
      throw Exception('로그인 정보를 가져오지 못했습니다.');
    }
    final baseUrl = ref.read(apiBaseUrlProvider).replaceAll(RegExp(r'/+$'), '');
    final response = await ref
        .read(scheduleHttpClientProvider)
        .post(
          Uri.parse('$baseUrl/schedules/$scheduleSeq/accept'),
          headers: {'Authorization': 'Bearer $token'},
        )
        .timeout(const Duration(seconds: 15));
    if (!ref.mounted || auth.currentUser?.uid != user.uid) {
      throw Exception('로그인 상태가 변경되었습니다.');
    }
    if (response.statusCode != 200) {
      String message = '일정을 수락하지 못했습니다. 다시 조회해 주세요.';
      try {
        final body = jsonDecode(utf8.decode(response.bodyBytes));
        if (body is Map && body['detail'] is String) {
          message = body['detail'] as String;
        }
      } catch (_) {
        // JSON이 아닌 서버 오류도 기본 안내로 표시한다.
      }
      throw Exception(message);
    }
  }

  // 수락자가 없는 일정의 변경 내용을 저장한다.
  // 실제 변경이 있으면 true, 기존 내용과 같으면 false를 반환한다.
  Future<bool> updateSchedule({
    required int scheduleSeq,
    required String familyRoomId,
    required String scheduleDate,
    required String startTime,
    required String endTime,
    required String name,
    required String memo,
  }) async {
    final auth = ref.read(firebaseAuthProvider);
    final user = auth.currentUser;

    if (user == null) {
      throw Exception('로그인이 필요합니다.');
    }

    final token = await user.getIdToken();

    if (!ref.mounted || auth.currentUser?.uid != user.uid) {
      throw Exception('로그인 상태가 변경되었습니다.');
    }

    if (token == null || token.isEmpty) {
      throw Exception('로그인 정보를 가져오지 못했습니다.');
    }

    final baseUrl = ref.read(apiBaseUrlProvider).replaceAll(RegExp(r'/+$'), '');

    final response = await ref
        .read(scheduleHttpClientProvider)
        .put(
          Uri.parse('$baseUrl/schedules/$scheduleSeq'),
          headers: {
            'Content-Type': 'application/json; charset=utf-8',
            'Authorization': 'Bearer $token',
          },
          body: jsonEncode({
            'family_room_id': familyRoomId,
            'schedule_date': scheduleDate,
            'start_time': startTime,
            'end_time': endTime,
            'schedule_name': name.trim().isEmpty ? null : name.trim(),
            'schedule_memo': memo.trim().isEmpty ? null : memo.trim(),
          }),
        )
        .timeout(const Duration(seconds: 15));

    if (!ref.mounted || auth.currentUser?.uid != user.uid) {
      throw Exception('로그인 상태가 변경되었습니다.');
    }

    if (response.statusCode != 200) {
      String message = '일정을 변경하지 못했습니다. 다시 시도해 주세요.';

      try {
        final body = jsonDecode(utf8.decode(response.bodyBytes));

        if (body is Map && body['detail'] is String) {
          message = body['detail'] as String;
        }
      } catch (_) {
        // JSON이 아닌 오류 응답에는 기본 안내를 사용한다.
      }

      throw Exception(message);
    }

    final body =
        jsonDecode(utf8.decode(response.bodyBytes)) as Map<String, dynamic>;

    return body['changed'] == true;
  }

  // 기존 담당자가 변경된 일정을 재수락하거나 거절한다.
  Future<void> respondScheduleChange({
    required int scheduleSeq,
    required int historySeq,
    required bool accepted,
  }) async {
    final auth = ref.read(firebaseAuthProvider);
    final user = auth.currentUser;

    if (user == null) {
      throw Exception('로그인이 필요합니다.');
    }

    final token = await user.getIdToken();

    if (!ref.mounted || auth.currentUser?.uid != user.uid) {
      throw Exception('로그인 상태가 변경되었습니다.');
    }

    if (token == null || token.isEmpty) {
      throw Exception('로그인 정보를 가져오지 못했습니다.');
    }

    final baseUrl = ref.read(apiBaseUrlProvider).replaceAll(RegExp(r'/+$'), '');

    final response = await ref
        .read(scheduleHttpClientProvider)
        .post(
          Uri.parse(
            '$baseUrl/schedules/$scheduleSeq'
            '/changes/$historySeq/respond',
          ),
          headers: {
            'Content-Type': 'application/json; charset=utf-8',
            'Authorization': 'Bearer $token',
          },
          body: jsonEncode({'accepted': accepted}),
        )
        .timeout(const Duration(seconds: 15));

    if (!ref.mounted || auth.currentUser?.uid != user.uid) {
      throw Exception('로그인 상태가 변경되었습니다.');
    }

    if (response.statusCode != 200) {
      String message = '재수락 요청에 응답하지 못했습니다. 다시 조회해 주세요.';

      try {
        final body = jsonDecode(utf8.decode(response.bodyBytes));

        if (body is Map && body['detail'] is String) {
          message = body['detail'] as String;
        }
      } catch (_) {
        // JSON이 아닌 오류 응답에는 기본 안내를 사용한다.
      }

      throw Exception(message);
    }
  }

  // 현재 담당자가 자신의 일정 참여만 철회한다.
  Future<bool> withdrawSchedule(Schedule item) async {
    final auth = ref.read(firebaseAuthProvider);
    final user = auth.currentUser;
    if (user == null || item.acceptedAt == null) {
      throw Exception('일정을 다시 조회한 후 시도해 주세요.');
    }
    final token = await user.getIdToken();
    if (!ref.mounted || auth.currentUser?.uid != user.uid || token == null) {
      throw Exception('로그인 상태가 변경되었습니다.');
    }
    final base = ref.read(apiBaseUrlProvider).replaceAll(RegExp(r'/+$'), '');
    final response = await ref
        .read(scheduleHttpClientProvider)
        .post(
          Uri.parse('$base/schedules/${item.seq}/withdraw'),
          headers: {
            'Authorization': 'Bearer $token',
            'Content-Type': 'application/json',
          },
          body: jsonEncode({
            'expected_history_seq': item.historySeq,
            'expected_accepted_at': item.acceptedAt!.toIso8601String(),
          }),
        )
        .timeout(const Duration(seconds: 15));
    if (!ref.mounted || auth.currentUser?.uid != user.uid) {
      throw Exception('로그인 상태가 변경되었습니다.');
    }
    final body = jsonDecode(utf8.decode(response.bodyBytes));
    if (response.statusCode != 200) {
      throw Exception(
        body is Map && body['detail'] is String
            ? body['detail']
            : '참여 철회를 처리하지 못했습니다.',
      );
    }
    return body['notification_published'] == true;
  }

  // 주보호자가 일정을 삭제하고 알림 발행 여부를 반환한다.
  Future<bool> deleteSchedule({
    required int scheduleSeq,
    required String familyRoomId,
  }) async {
    final auth = ref.read(firebaseAuthProvider);
    final user = auth.currentUser;
    if (user == null) throw Exception('로그인이 필요합니다.');

    final baseUrl = ref.read(apiBaseUrlProvider).replaceAll(RegExp(r'/+$'), '');
    final uri = Uri.parse(
      '$baseUrl/schedules/$scheduleSeq',
    ).replace(queryParameters: {'family_room_id': familyRoomId});

    for (var attempt = 0; attempt < 2; attempt++) {
      if (!ref.mounted || auth.currentUser?.uid != user.uid) {
        throw Exception('로그인 상태가 변경되었습니다.');
      }

      final token = await user.getIdToken(attempt == 1);

      if (!ref.mounted || auth.currentUser?.uid != user.uid) {
        throw Exception('로그인 상태가 변경되었습니다.');
      }
      if (token == null || token.isEmpty) {
        throw Exception('로그인 정보를 가져오지 못했습니다.');
      }

      final response = await ref
          .read(scheduleHttpClientProvider)
          .delete(
            uri,
            headers: {
              'Authorization': 'Bearer $token',
              'Accept': 'application/json',
            },
          )
          .timeout(const Duration(seconds: 45));

      if (!ref.mounted || auth.currentUser?.uid != user.uid) {
        throw Exception('로그인 상태가 변경되었습니다.');
      }
      if (response.statusCode == 401 && attempt == 0) continue;

      if (response.statusCode == 403) {
        throw Exception('현재 공간의 주보호자만 일정을 삭제할 수 있습니다.');
      }
      if (response.statusCode != 200) {
        throw Exception(getServerError(response));
      }

      final body = jsonDecode(utf8.decode(response.bodyBytes));
      if (body is! Map ||
          body['deleted'] != true ||
          body['schedule_seq'] != scheduleSeq) {
        throw Exception('삭제 결과를 확인하지 못했습니다. 목록을 다시 조회해 주세요.');
      }

      return body['notification_published'] == true;
    }

    throw Exception('다시 로그인해 주세요.');
  }
} // class
