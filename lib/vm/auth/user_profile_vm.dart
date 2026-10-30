import 'dart:async';
import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:ondolbom/model/auth/user_profile.dart';
import 'package:ondolbom/vm/auth/auth_vm.dart';

// 기본값은 Android 에뮬레이터에서 호스트 PC에 접근하는 주소다.
// 실제 기기·배포 환경에서는 --dart-define=API_BASE_URL=...로 지정한다.
final apiBaseUrlProvider = Provider<String>(
  (ref) => const String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: 'http://10.0.2.2:8000',
  ),
);
final authHttpClientProvider = Provider.autoDispose<http.Client>((ref) {
  // 사용이 끝난 HTTP 클라이언트는 닫아 연결 리소스를 정리한다.
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

// Firebase 인증은 본인 확인에만 사용하고 서비스 진입은 재활성화 전까지 차단한다.
class AccountInactiveException extends ProfileLoadException {
  const AccountInactiveException(this.reactivationUntil, this.canReactivate)
    : super('탈퇴 처리된 계정입니다.');
  final String reactivationUntil;
  final bool canReactivate;
}

// 최초 등록 요청 상태를 폼과 홈의 버튼 활성화 여부에 공유한다.
final profileRegistrationProvider =
    NotifierProvider.autoDispose<ProfileRegistrationVm, AsyncValue<void>>(
      ProfileRegistrationVm.new,
    );

class ProfileRegistrationVm extends Notifier<AsyncValue<void>> {
  @override
  AsyncValue<void> build() => const AsyncData(null);

  Future<void> register(String name, String phone) async {
    // 같은 화면에서 저장 버튼을 연속으로 눌러도 요청은 한 번씩만 실행한다.
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
          // 요청 중 계정이 바뀌면 이전 계정의 입력으로 새 계정을 등록하지 않는다.
          if (auth.currentUser?.uid != user.uid) {
            throw const ProfileLoadException('로그인 계정이 변경되었습니다.');
          }
          // 최초 401일 때만 토큰을 강제 갱신하고 한 번 더 시도한다.
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
                // UID·이메일·내부 ID는 보내지 않는다. 서버가 검증 토큰에서 결정한다.
                // 전화번호의 최종 형식 검증과 하이픈 정규화도 서버가 담당한다.
                body: jsonEncode({'name': name.trim(), 'phone': phone.trim()}),
              )
              .timeout(const Duration(seconds: 15));
          if (response.statusCode == 401 && attempt == 0) continue;
          // 이메일 인증 직후의 캐시된 토큰이라면 한 번 갱신하되 서버 인증 조건은 우회하지 않는다.
          if (response.statusCode == 403 &&
              attempt == 0 &&
              getProfileAccessError(response) == '회원가입 이메일 인증을 먼저 완료해 주세요.') {
            continue;
          }
          if (response.statusCode != 200) {
            throw ProfileLoadException(switch (response.statusCode) {
              401 => '다시 로그인해 주세요.',
              403 => getProfileAccessError(response),
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
          // 응답 필드가 유효한지 확인한 뒤 서버에서 최신 프로필을 다시 조회한다.
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
    // 화면 이동 등으로 provider가 폐기된 경우에는 완료 상태를 쓰지 않는다.
    if (ref.mounted) state = result;
  }
}

// 로그인 사용자가 바뀌면 재조회하고, 화면에서 사라지면 이전 요청 상태를 폐기한다.
final userProfileProvider = FutureProvider.autoDispose<UserProfile?>(
  // 인증·설정 오류를 자동 반복하지 않는다. 화면의 재시도 버튼으로 다시 실행한다.
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
        // 서버에서 서명 검증할 ID 토큰을 사용한다. Firebase UID 자체는 인증 수단이 아니다.
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
        if (response.statusCode == 403) {
          final payload = jsonDecode(utf8.decode(response.bodyBytes));
          final detail = payload is Map ? payload['detail'] : null;
          if (detail is Map && detail['code'] == 'account_inactive') {
            throw AccountInactiveException(
              detail['reactivation_until'].toString(),
              detail['can_reactivate'] == true,
            );
          }
        }
        if (response.statusCode != 200) {
          throw ProfileLoadException(switch (response.statusCode) {
            401 => '로그인이 만료되었습니다. 다시 로그인해 주세요.',
            403 => getProfileAccessError(response),
            503 => getServerError(response),
            _ => '사용자 정보를 확인하지 못했습니다. 다시 시도해 주세요.',
          });
        }
        final body =
            jsonDecode(utf8.decode(response.bodyBytes)) as Map<String, dynamic>;
        // 정상 응답에서 명시한 미등록만 null이다. 통신·서버 오류와 혼동하지 않는다.
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
// 서버가 반환한 오류 안내를 확인한다.
String getServerError(http.Response response) {
  try {
    final body =
        jsonDecode(utf8.decode(response.bodyBytes)) as Map<String, dynamic>;

    return body['detail'] as String? ?? '서버 설정을 확인해 주세요.';
  } catch (_) {
    return '서버 응답을 확인하지 못했습니다.';
  }
}

// 이메일 미인증과 탈퇴 계정을 같은 이용 제한 문구로 오해하지 않도록 구분한다.
String getProfileAccessError(http.Response response) {
  final detail = getServerError(response);
  if (detail == '회원가입 이메일 인증을 먼저 완료해 주세요.' || detail == '탈퇴 처리된 계정입니다.') {
    return detail;
  }
  return '이 계정은 서비스를 이용할 수 없습니다.';
}
