import 'dart:async';
import 'dart:convert';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:ondolbom/model/inquiries/inquiry.dart';
import 'package:ondolbom/vm/auth/auth_vm.dart';
import 'package:ondolbom/vm/auth/user_profile_vm.dart' show apiBaseUrlProvider;

class InquiryFailure implements Exception {
  const InquiryFailure(this.message);
  final String message;
  @override
  String toString() => message;
}

final inquiryHttpProvider = Provider.autoDispose<http.Client>((ref) {
  final client = http.Client();
  ref.onDispose(client.close);
  return client;
});

final inquiryApiProvider = Provider.autoDispose<InquiryApi>((ref) {
  // 계정 전환 시 API와 목록·상세 상태를 함께 폐기한다.
  ref.watch(authUserProvider);
  final auth = ref.watch(firebaseAuthProvider);
  final user = auth.currentUser;
  return InquiryApi(
    ref.watch(apiBaseUrlProvider),
    ref.watch(inquiryHttpProvider),
    () async {
      if (user == null || auth.currentUser?.uid != user.uid) {
        throw const InquiryFailure('다시 로그인해 주세요.');
      }
      final token = await user.getIdToken();
      if (auth.currentUser?.uid != user.uid || token == null) {
        throw const InquiryFailure('다시 로그인해 주세요.');
      }
      return token;
    },
  );
});

class InquiryApi {
  InquiryApi(
    this.base,
    this.client,
    this.getToken, {
    this.tokenTimeout = const Duration(seconds: 10),
  });
  final String base;
  final http.Client client;
  final Future<String> Function() getToken;
  final Duration tokenTimeout;
  Future<Map<String, dynamic>> request(
    String path, {
    Map<String, dynamic>? body,
  }) async {
    try {
      // Firebase 토큰 발급도 네트워크를 기다릴 수 있으므로 HTTP와 별도로 제한한다.
      final token = await getToken().timeout(
        tokenTimeout,
        onTimeout: () {
          throw const InquiryFailure(
            '로그인 정보를 확인하는 시간이 초과되었습니다. 네트워크 연결을 확인한 후 다시 시도해 주세요.',
          );
        },
      );
      final uri = Uri.parse(
        '${base.replaceAll(RegExp(r'/+$'), '')}/inquiries$path',
      );
      final headers = {
        'Authorization': 'Bearer $token',
        'Content-Type': 'application/json',
      };
      final response =
          await (body == null
                  ? client.get(uri, headers: headers)
                  : client.post(uri, headers: headers, body: jsonEncode(body)))
              .timeout(const Duration(seconds: 20));
      if (response.statusCode != 200 && response.statusCode != 201) {
        throw InquiryFailure(switch (response.statusCode) {
          401 => '다시 로그인해 주세요.',
          403 => '사용자 등록 상태 또는 공간 참여 권한을 확인해 주세요.',
          404 => '문의를 찾을 수 없습니다.',
          422 => '제목·내용 길이를 확인하고 이모지는 제외해 주세요.',
          503 =>
            body == null
                ? '문의 서버 또는 DB 연결을 확인해 주세요. 잠시 후 다시 시도해 주세요.'
                : '저장 결과를 확인하지 못했습니다. 목록을 확인한 후 다시 시도해 주세요.',
          _ =>
            body == null
                ? '문의를 불러오지 못했습니다.'
                : '저장 결과를 확인하지 못했습니다. 목록을 확인한 후 다시 시도해 주세요.',
        });
      }
      return jsonDecode(utf8.decode(response.bodyBytes))
          as Map<String, dynamic>;
    } on InquiryFailure {
      rethrow;
    } catch (_) {
      throw InquiryFailure(
        body == null
            ? '서버 연결을 확인해 주세요.'
            : '저장 결과를 확인하지 못했습니다. 목록을 확인한 후 다시 시도해 주세요.',
      );
    }
  }
}

class InquiryPage {
  const InquiryPage(this.items, this.nextCursor);
  final List<Inquiry> items;
  final int? nextCursor;
}

final inquiriesProvider = FutureProvider.autoDispose.family<InquiryPage, int?>((
  ref,
  cursor,
) async {
  final json = await ref
      .watch(inquiryApiProvider)
      .request(cursor == null ? '' : '?before_seq=$cursor');
  return InquiryPage(
    (json['items'] as List<dynamic>)
        .map((e) => Inquiry.fromJson(e as Map<String, dynamic>))
        .toList(),
    json['next_cursor'] as int?,
  );
}, retry: (_, _) => null); // 실패를 무한 로딩처럼 숨기지 않고 화면의 수동 재시도를 사용한다.
final inquiryDetailProvider = FutureProvider.autoDispose.family<Inquiry, int>(
  (ref, id) async =>
      Inquiry.fromJson(await ref.watch(inquiryApiProvider).request('/$id')),
  retry: (_, _) => null,
);
final inquiryCreateProvider =
    NotifierProvider.autoDispose<InquiryCreateVm, AsyncValue<int?>>(
      InquiryCreateVm.new,
    );

class InquiryCreateVm extends Notifier<AsyncValue<int?>> {
  @override
  AsyncValue<int?> build() {
    ref.watch(inquiryApiProvider);
    return const AsyncData(null);
  }

  Future<void> create(
    String title,
    String content, {
    String? familyRoomId,
  }) async {
    if (state.isLoading) return;
    final api = ref.read(inquiryApiProvider);
    state = const AsyncLoading();
    final result = await AsyncValue.guard(() async {
      final data = await api.request(
        '',
        body: {
          'question_title': title.trim(),
          'question_content': content.trim(),
          'family_room_id': familyRoomId,
        },
      );
      return data['question_seq'] as int;
    });
    if (!ref.mounted || !identical(ref.read(inquiryApiProvider), api)) return;
    state = result;
    if (!result.hasError) ref.invalidate(inquiriesProvider);
  }
}
