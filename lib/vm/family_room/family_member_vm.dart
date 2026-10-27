import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;

import 'package:ondolbom/model/family/family_member.dart';
import 'package:ondolbom/vm/auth/auth_vm.dart';
import 'package:ondolbom/vm/auth/user_profile_vm.dart';

// 가족 목록 요청에 사용할 클라이언트
final familyMemberHttpClientProvider = Provider<http.Client>((ref) {
  final client = http.Client();

  ref.onDispose(client.close);

  return client;
});

// 가족 목록 VM
final familyMemberVmProvider = Provider<FamilyMemberVm>((ref) {
  return FamilyMemberVm(ref);
});

// 로그인 계정과 공간별로 가족 목록을 구분한다.
final familyMembersProvider = FutureProvider.autoDispose
    .family<List<FamilyMember>, String>((ref, familyRoomId) async {
      final user = await ref.watch(authUserProvider.future);

      if (user == null) {
        throw Exception('로그인이 필요합니다.');
      }

      return ref.read(familyMemberVmProvider).fetchMembers(familyRoomId);
    }, retry: (retryCount, error) => null);

class FamilyMemberVm {
  FamilyMemberVm(this.ref);

  final Ref ref;

  // 요청 중 로그인 계정이 변경되었는지 확인한다.
  void checkLoginUser(String uid) {
    if (!ref.mounted ||
        ref.read(firebaseAuthProvider).currentUser?.uid != uid) {
      throw Exception('로그인 상태가 변경되었습니다.');
    }
  }

  // 선택한 가족 공간의 현재 참여 가족을 조회한다.
  Future<List<FamilyMember>> fetchMembers(String familyRoomId) async {
    final user = ref.read(firebaseAuthProvider).currentUser;

    if (user == null) {
      throw Exception('로그인이 필요합니다.');
    }

    final uid = user.uid;
    final token = await user.getIdToken();

    checkLoginUser(uid);

    if (token == null || token.isEmpty) {
      throw Exception('로그인 정보를 가져오지 못했습니다.');
    }

    final baseUrl = ref.read(apiBaseUrlProvider).replaceAll(RegExp(r'/+$'), '');

    final response = await ref
        .read(familyMemberHttpClientProvider)
        .get(
          Uri.parse(
            '$baseUrl/family-room/'
            '${Uri.encodeComponent(familyRoomId)}/members',
          ),
          headers: {'Authorization': 'Bearer $token'},
        )
        .timeout(const Duration(seconds: 15));

    checkLoginUser(uid);

    if (response.statusCode != 200) {
      String message = '가족 목록을 불러오지 못했습니다.';

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

    final results = body['results'] as List<dynamic>;

    return results.map((item) {
      return FamilyMember.fromJson(item as Map<String, dynamic>);
    }).toList();
  }
}
