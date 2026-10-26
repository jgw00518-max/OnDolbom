import 'dart:convert';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:ondolbom/model/notices/notice.dart';
import 'package:ondolbom/vm/auth/auth_vm.dart';
import 'package:ondolbom/vm/auth/user_profile_vm.dart' show apiBaseUrlProvider;

final noticeClientProvider = Provider.autoDispose<http.Client>((ref) {
  final client = http.Client();
  ref.onDispose(client.close);
  return client;
});
final noticeApiProvider = Provider.autoDispose<NoticeApi>((ref) {
  ref.watch(authUserProvider);
  final auth = ref.watch(firebaseAuthProvider);
  final user = auth.currentUser;
  return NoticeApi(
    ref.watch(apiBaseUrlProvider),
    ref.watch(noticeClientProvider),
    () async {
      if (user == null || auth.currentUser?.uid != user.uid) {
        throw const NoticeFailure('다시 로그인해 주세요.');
      }
      final token = await user.getIdToken();
      if (token == null || auth.currentUser?.uid != user.uid) {
        throw const NoticeFailure('다시 로그인해 주세요.');
      }
      return token;
    },
  );
});

class NoticeFailure implements Exception {
  const NoticeFailure(this.message);
  final String message;
  @override
  String toString() => message;
}

class NoticeApi {
  NoticeApi(this.base, this.client, this.token);
  final String base;
  final http.Client client;
  final Future<String> Function() token;
  Future<Map<String, dynamic>> get(String path) async {
    try {
      // 앱은 각자 실행한 사용자 API로 접속한다. 관리자 서버 주소는 필요하지 않다.
      final idToken = await token().timeout(const Duration(seconds: 10));
      final response = await client
          .get(
            Uri.parse('${base.replaceAll(RegExp(r'/+$'), '')}/notices$path'),
            headers: {'Authorization': 'Bearer $idToken'},
          )
          .timeout(const Duration(seconds: 20));
      if (response.statusCode != 200) {
        throw NoticeFailure(switch (response.statusCode) {
          401 => '다시 로그인해 주세요.',
          404 => '삭제되었거나 존재하지 않는 공지입니다.',
          _ => '공지사항을 불러오지 못했습니다. 서버와 DB 연결을 확인해 주세요.',
        });
      }
      return jsonDecode(utf8.decode(response.bodyBytes))
          as Map<String, dynamic>;
    } on NoticeFailure {
      rethrow;
    } catch (_) {
      throw const NoticeFailure(
        '공지사항 연결 시간이 초과되었거나 응답을 확인하지 못했습니다. 다시 시도해 주세요.',
      );
    }
  }
}

typedef NoticeKey = ({String adminId, String id});
typedef NoticePage = ({List<Notice> items, bool hasMore});
final noticesProvider = FutureProvider.autoDispose.family<NoticePage, int>((
  ref,
  offset,
) async {
  final result = await ref
      .watch(noticeApiProvider)
      .get('?limit=30&offset=$offset');
  return (
    items: (result['items'] as List<dynamic>)
        .map((v) => Notice.fromJson(v as Map<String, dynamic>))
        .toList(),
    hasMore: result['has_more'] as bool,
  );
}, retry: (_, _) => null);
final noticeDetailProvider = FutureProvider.autoDispose.family<Notice, NoticeKey>(
  (ref, key) async => Notice.fromJson(
    await ref
        .watch(noticeApiProvider)
        .get(
          '/${Uri.encodeComponent(key.adminId)}/${Uri.encodeComponent(key.id)}',
        ),
  ),
  retry: (_, _) => null,
);
