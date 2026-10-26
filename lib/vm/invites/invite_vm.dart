import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;

import 'package:ondolbom/model/invites/family_invite.dart';
import 'package:ondolbom/vm/auth/auth_vm.dart';
import 'package:ondolbom/vm/auth/user_profile_vm.dart';

// 초대 API 요청에 사용할 클라이언트
final inviteHttpClientProvider = Provider<http.Client>((ref) {
  final client = http.Client();

  ref.onDispose(client.close);

  return client;
});

// 화면에서 사용할 초대 VM
final inviteVmProvider = Provider<InviteVm>((ref) {
  return InviteVm(ref);
});

// 로그인 계정이 변경되면 받은 초대도 다시 조회한다.
final receivedInvitesProvider = FutureProvider.autoDispose<List<FamilyInvite>>((
  ref,
) async {
  final user = await ref.watch(authUserProvider.future);

  if (user == null) {
    throw Exception('로그인이 필요합니다.');
  }

  return ref.read(inviteVmProvider).fetchReceivedInvites();
}, retry: (retryCount, error) => null);

// 로그인한 사용자가 주보호자로 관리하는 공간의 보낸 초대를 조회한다.
final sentInvitesProvider = FutureProvider.autoDispose<List<FamilyInvite>>((
  ref,
) async {
  final user = await ref.watch(authUserProvider.future);

  if (user == null) {
    throw Exception('로그인이 필요합니다.');
  }

  return ref.read(inviteVmProvider).fetchSentInvites();
}, retry: (retryCount, error) => null);

class InviteVm {
  InviteVm(this.ref);

  final Ref ref;

  String get baseUrl {
    return ref.read(apiBaseUrlProvider).replaceAll(RegExp(r'/+$'), '');
  }

  // 요청할 때 현재 사용자의 로그인 토큰을 가져온다.
  Future<String> getLoginToken(String uid) async {
    final auth = ref.read(firebaseAuthProvider);
    final user = auth.currentUser;

    if (user == null || user.uid != uid) {
      throw Exception('로그인 상태가 변경되었습니다.');
    }

    final token = await user.getIdToken();

    checkLoginUser(uid);

    if (token == null || token.isEmpty) {
      throw Exception('로그인 정보를 가져오지 못했습니다.');
    }

    return token;
  }

  // 요청 도중 로그아웃하거나 계정을 바꿨는지 확인한다.
  void checkLoginUser(String uid) {
    if (!ref.mounted ||
        ref.read(firebaseAuthProvider).currentUser?.uid != uid) {
      throw Exception('로그인 상태가 변경되었습니다.');
    }
  }

  // 서버가 보낸 오류 메시지를 읽는다.
  String getErrorMessage(http.Response response, String defaultMessage) {
    try {
      final body = jsonDecode(utf8.decode(response.bodyBytes));

      if (body is Map && body['detail'] is String) {
        return body['detail'] as String;
      }
    } catch (_) {
      // JSON이 아닌 응답이면 기본 안내를 사용한다.
    }

    return defaultMessage;
  }

  // 로그인한 사용자가 받은 대기 초대를 조회한다.
  Future<List<FamilyInvite>> fetchReceivedInvites() async {
    final user = ref.read(firebaseAuthProvider).currentUser;

    if (user == null) {
      throw Exception('로그인이 필요합니다.');
    }

    final uid = user.uid;
    final token = await getLoginToken(uid);

    final response = await ref
        .read(inviteHttpClientProvider)
        .get(
          Uri.parse('$baseUrl/invites/received'),
          headers: {'Authorization': 'Bearer $token'},
        )
        .timeout(const Duration(seconds: 15));

    checkLoginUser(uid);

    if (response.statusCode != 200) {
      throw Exception(getErrorMessage(response, '받은 초대를 불러오지 못했습니다.'));
    }

    final body =
        jsonDecode(utf8.decode(response.bodyBytes)) as Map<String, dynamic>;

    final results = body['results'] as List<dynamic>;

    return results.map((item) {
      return FamilyInvite.fromJson(item as Map<String, dynamic>);
    }).toList();
  }

  // 본인에게 온 초대를 수락한다.
  Future<void> acceptInvite(String inviteId) async {
    final user = ref.read(firebaseAuthProvider).currentUser;

    if (user == null) {
      throw Exception('로그인이 필요합니다.');
    }

    final uid = user.uid;
    final token = await getLoginToken(uid);

    final response = await ref
        .read(inviteHttpClientProvider)
        .post(
          Uri.parse('$baseUrl/invites/${Uri.encodeComponent(inviteId)}/accept'),
          headers: {'Authorization': 'Bearer $token'},
        )
        .timeout(const Duration(seconds: 15));

    checkLoginUser(uid);

    if (response.statusCode != 200) {
      throw Exception(getErrorMessage(response, '초대를 수락하지 못했습니다.'));
    }
  } // build

  // 주보호자가 가족 공간에 초대를 등록한다.
  Future<bool> createInvite({
    required String familyRoomId,
    required String email,
  }) async {
    final user = ref.read(firebaseAuthProvider).currentUser;

    if (user == null) {
      throw Exception('로그인이 필요합니다.');
    }

    final uid = user.uid;
    final token = await getLoginToken(uid);

    final response = await ref
        .read(inviteHttpClientProvider)
        .post(
          Uri.parse('$baseUrl/invites'),
          headers: {
            'Content-Type': 'application/json; charset=utf-8',
            'Authorization': 'Bearer $token',
          },
          body: jsonEncode({
            'family_room_id': familyRoomId,
            'invite_email': email.trim(),
          }),
        )
        .timeout(const Duration(seconds: 45));

    checkLoginUser(uid);

    if (response.statusCode != 201) {
      throw Exception(getErrorMessage(response, '초대를 등록하지 못했습니다.'));
    }
    final body = jsonDecode(utf8.decode(response.bodyBytes));
    return body['email_sent'] == true;
  } // build

  // 본인에게 온 초대를 거절한다.
  Future<void> rejectInvite(String inviteId) async {
    final user = ref.read(firebaseAuthProvider).currentUser;

    if (user == null) {
      throw Exception('로그인이 필요합니다.');
    }

    final uid = user.uid;
    final token = await getLoginToken(uid);

    final response = await ref
        .read(inviteHttpClientProvider)
        .post(
          Uri.parse('$baseUrl/invites/${Uri.encodeComponent(inviteId)}/reject'),
          headers: {'Authorization': 'Bearer $token'},
        )
        .timeout(const Duration(seconds: 15));

    checkLoginUser(uid);

    if (response.statusCode != 200) {
      throw Exception(getErrorMessage(response, '초대를 거절하지 못했습니다.'));
    }
  }

  // 서버에서 보낸 초대 목록을 가져온다.
  Future<List<FamilyInvite>> fetchSentInvites() async {
    final user = ref.read(firebaseAuthProvider).currentUser;

    if (user == null) {
      throw Exception('로그인이 필요합니다.');
    }

    final uid = user.uid;
    final token = await getLoginToken(uid);

    final response = await ref
        .read(inviteHttpClientProvider)
        .get(
          Uri.parse('$baseUrl/invites/sent'),
          headers: {'Authorization': 'Bearer $token'},
        )
        .timeout(const Duration(seconds: 15));

    checkLoginUser(uid);

    if (response.statusCode != 200) {
      throw Exception(getErrorMessage(response, '보낸 초대를 불러오지 못했습니다.'));
    }

    final body =
        jsonDecode(utf8.decode(response.bodyBytes)) as Map<String, dynamic>;

    final results = body['results'] as List<dynamic>;

    return results.map((item) {
      return FamilyInvite.fromJson(item as Map<String, dynamic>);
    }).toList();
  } // build

  // 현재 주보호자가 보낸 초대를 취소한다.
  Future<void> cancelInvite(String inviteId) async {
    final user = ref.read(firebaseAuthProvider).currentUser;

    if (user == null) {
      throw Exception('로그인이 필요합니다.');
    }

    final uid = user.uid;
    final token = await getLoginToken(uid);

    final response = await ref
        .read(inviteHttpClientProvider)
        .post(
          Uri.parse('$baseUrl/invites/${Uri.encodeComponent(inviteId)}/cancel'),
          headers: {'Authorization': 'Bearer $token'},
        )
        .timeout(const Duration(seconds: 15));

    checkLoginUser(uid);

    if (response.statusCode != 200) {
      throw Exception(getErrorMessage(response, '초대를 취소하지 못했습니다.'));
    }
  }
} // class
