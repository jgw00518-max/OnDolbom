import 'dart:async';
import 'dart:convert';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:ondolbom/model/auth/user_profile.dart';
import 'package:ondolbom/vm/auth/auth_vm.dart';
import 'package:ondolbom/vm/auth/user_profile_vm.dart';

final profileEditProvider =
    NotifierProvider.autoDispose<ProfileEditVm, AsyncValue<UserProfile?>>(
      ProfileEditVm.new,
    );

/// 최초 등록 API를 재사용하지 않고 현재 로그인 사용자의 수정 API를 호출한다.
class ProfileEditVm extends Notifier<AsyncValue<UserProfile?>> {
  int _generation = 0;
  @override
  AsyncValue<UserProfile?> build() {
    _generation++;
    ref.watch(authUserProvider);
    return const AsyncData(null);
  }

  Future<bool> save(String name, String phone) async {
    if (state.isLoading) return false;
    final generation = _generation;
    state = const AsyncLoading();
    final result = await AsyncValue.guard<UserProfile?>(() async {
      final auth = ref.read(firebaseAuthProvider);
      final user = auth.currentUser;
      if (user == null) throw const ProfileLoadException('다시 로그인해 주세요.');
      final base = ref.read(apiBaseUrlProvider).replaceAll(RegExp(r'/+$'), '');
      final client = ref.read(authHttpClientProvider);
      try {
        for (var attempt = 0; attempt < 2; attempt++) {
          final token = await user
              .getIdToken(attempt == 1)
              .timeout(const Duration(seconds: 10));
          if (!ref.mounted ||
              generation != _generation ||
              auth.currentUser?.uid != user.uid) {
            throw const ProfileLoadException('로그인 계정이 변경되었습니다.');
          }
          if (token == null || token.isEmpty) {
            throw const ProfileLoadException('다시 로그인해 주세요.');
          }
          final response = await client
              .put(
                Uri.parse('$base/auth/profile'),
                headers: {
                  'Authorization': 'Bearer $token',
                  'Content-Type': 'application/json; charset=utf-8',
                },
                body: jsonEncode({'name': name.trim(), 'phone': phone.trim()}),
              )
              .timeout(const Duration(seconds: 15));
          if (!ref.mounted ||
              generation != _generation ||
              auth.currentUser?.uid != user.uid) {
            throw const ProfileLoadException('로그인 계정이 변경되었습니다.');
          }
          if (response.statusCode == 401 && attempt == 0) continue;
          if (response.statusCode != 200) {
            throw ProfileLoadException(switch (response.statusCode) {
              401 => '다시 로그인해 주세요.',
              403 => '이 계정은 사용자 정보를 수정할 수 없습니다.',
              404 => '등록된 사용자 정보를 찾을 수 없습니다.',
              422 => '이름·전화번호 형식을 확인해 주세요.',
              _ => '저장 결과를 확인하지 못했습니다. 프로필을 다시 조회해 주세요.',
            });
          }
          final body =
              jsonDecode(utf8.decode(response.bodyBytes))
                  as Map<String, dynamic>;
          if (body['registered'] != true ||
              body['user'] is! Map<String, dynamic>) {
            throw const FormatException();
          }
          final profile = UserProfile.fromJson(
            body['user'] as Map<String, dynamic>,
          );
          ref.invalidate(userProfileProvider);
          return profile;
        }
        throw const ProfileLoadException('다시 로그인해 주세요.');
      } on ProfileLoadException {
        rethrow;
      } on TimeoutException {
        throw const ProfileLoadException(
          '응답 시간이 초과되었습니다. 저장되었을 수 있으니 프로필을 다시 조회해 주세요.',
        );
      } catch (_) {
        throw const ProfileLoadException(
          '저장 결과를 확인하지 못했습니다. 입력을 유지했으니 프로필을 다시 조회해 주세요.',
        );
      }
    });
    // 계정 전환이나 화면 폐기 후 도착한 수정 결과를 새 계정에 노출하지 않는다.
    if (!ref.mounted || generation != _generation) return false;
    state = result;
    return !result.hasError;
  }
}
