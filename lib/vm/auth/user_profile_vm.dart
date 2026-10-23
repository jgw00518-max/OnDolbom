import 'dart:async';
import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:ondolbom/model/auth/user_profile.dart';
import 'package:ondolbom/vm/auth/auth_vm.dart';

final apiBaseUrlProvider = Provider<String>(
  (ref) => const String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: 'http://10.0.2.2:8000',
  ),
);
final authHttpClientProvider = Provider.autoDispose<http.Client>((ref) {
  final client = http.Client();
  ref.onDispose(client.close);
  return client;
});

class ProfileLoadException implements Exception {
  const ProfileLoadException(this.message);
  final String message;
  @override
  String toString() => message;
}

final profileRegistrationProvider =
    NotifierProvider.autoDispose<ProfileRegistrationVm, AsyncValue<void>>(
      ProfileRegistrationVm.new,
    );

class ProfileRegistrationVm extends Notifier<AsyncValue<void>> {
  @override
  AsyncValue<void> build() => const AsyncData(null);

  Future<void> register(String name, String phone) async {
    if (state.isLoading) return;
    state = const AsyncLoading();
    final result = await AsyncValue.guard(() async {
      final auth = ref.read(firebaseAuthProvider);
      final user = auth.currentUser;
      if (user == null) throw const ProfileLoadException('다시 로그인해 주세요.');
      final uri = Uri.parse(
        '${ref.read(apiBaseUrlProvider).replaceAll(RegExp(r'/+$'), '')}/auth/profile',
      );
      final client = ref.read(authHttpClientProvider);
      try {
        for (var attempt = 0; attempt < 2; attempt++) {
          if (auth.currentUser?.uid != user.uid) {
            throw const ProfileLoadException('로그인 계정이 변경되었습니다.');
          }
          final token = await user.getIdToken(attempt == 1);
          if (token == null || token.isEmpty) {
            throw const ProfileLoadException('다시 로그인해 주세요.');
          }
          final response = await client
              .post(
                uri,
                headers: {
                  'Authorization': 'Bearer $token',
                  'Content-Type': 'application/json; charset=utf-8',
                },
                body: jsonEncode({'name': name.trim(), 'phone': phone.trim()}),
              )
              .timeout(const Duration(seconds: 15));
          if (response.statusCode == 401 && attempt == 0) continue;
          if (response.statusCode != 200) {
            throw ProfileLoadException(switch (response.statusCode) {
              401 => '다시 로그인해 주세요.',
              403 => '이 계정은 서비스를 이용할 수 없습니다.',
              409 => '계정 연결 정보가 충돌합니다. 기존 계정을 확인해 주세요.',
              422 => '이름·전화번호 형식과 로그인 이메일을 확인해 주세요.',
              _ => '저장하지 못했습니다. 잠시 후 다시 시도해 주세요.',
            });
          }
          final body =
              jsonDecode(utf8.decode(response.bodyBytes))
                  as Map<String, dynamic>;
          if (body['registered'] != true ||
              body['user'] is! Map<String, dynamic>) {
            throw const FormatException();
          }
          UserProfile.fromJson(body['user'] as Map<String, dynamic>);
          if (ref.mounted && auth.currentUser?.uid == user.uid) {
            ref.invalidate(userProfileProvider);
          }
          return;
        }
      } on ProfileLoadException {
        rethrow;
      } on TimeoutException {
        throw const ProfileLoadException(
          '서버 응답 시간이 초과되었습니다. 다시 저장해도 중복 등록되지 않습니다.',
        );
      } catch (_) {
        throw const ProfileLoadException(
          '서버 연결 또는 응답을 확인하지 못했습니다. 다시 시도해 주세요.',
        );
      }
    });
    if (ref.mounted) state = result;
  }
}

// 로그인 사용자가 바뀌면 재조회하고, 화면에서 사라지면 이전 요청 상태를 폐기한다.
final userProfileProvider = FutureProvider.autoDispose<UserProfile?>(
  retry: (_, _) => null,
  (ref) async {
    final session = await ref.watch(authUserProvider.future);
    if (session == null) return null;
    final auth = ref.watch(firebaseAuthProvider);
    final client = ref.watch(authHttpClientProvider);
    final uri = Uri.parse(
      '${ref.watch(apiBaseUrlProvider).replaceAll(RegExp(r'/+$'), '')}/auth/me',
    );
    try {
      for (var attempt = 0; attempt < 2; attempt++) {
        final user = auth.currentUser;
        if (user == null || user.uid != session.uid) {
          throw const ProfileLoadException('로그인 상태가 변경되었습니다. 다시 로그인해 주세요.');
        }
        final token = await user.getIdToken(attempt == 1);
        if (token == null || token.isEmpty) {
          throw const ProfileLoadException('로그인 토큰을 가져오지 못했습니다. 다시 로그인해 주세요.');
        }
        final response = await client
            .get(
              uri,
              headers: {
                'Authorization': 'Bearer $token',
                'Accept': 'application/json',
              },
            )
            .timeout(const Duration(seconds: 15));
        if (response.statusCode == 401 && attempt == 0) continue;
        if (response.statusCode != 200) {
          throw ProfileLoadException(switch (response.statusCode) {
            401 => '로그인이 만료되었습니다. 다시 로그인해 주세요.',
            403 => '이 계정은 서비스를 이용할 수 없습니다.',
            503 => '서버의 인증 설정 또는 DB 연결을 확인해 주세요.',
            _ => '사용자 정보를 확인하지 못했습니다. 다시 시도해 주세요.',
          });
        }
        final body =
            jsonDecode(utf8.decode(response.bodyBytes)) as Map<String, dynamic>;
        if (body['registered'] == false && body['user'] == null) return null;
        if (body['registered'] != true ||
            body['user'] is! Map<String, dynamic>) {
          throw const FormatException();
        }
        return UserProfile.fromJson(body['user'] as Map<String, dynamic>);
      }
      throw const ProfileLoadException('다시 로그인해 주세요.');
    } on ProfileLoadException {
      rethrow;
    } on TimeoutException {
      throw const ProfileLoadException('서버 응답 시간이 초과되었습니다. 다시 시도해 주세요.');
    } catch (_) {
      throw const ProfileLoadException('서버 연결 또는 응답을 확인하지 못했습니다. 다시 시도해 주세요.');
    }
  },
);
