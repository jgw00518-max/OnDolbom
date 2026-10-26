import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:kakao_flutter_sdk_user/kakao_flutter_sdk_user.dart';

class KakaoLoginCancelled implements Exception {}

class KakaoLoginFailure implements Exception {
  const KakaoLoginFailure(this.message);
  final String message;
}

/// 브라우저가 SDK에 결과를 돌려주지 않아도 앱 복귀 후 대기를 해제한다.
/// SDK의 늦은 응답은 이 요청 안에서만 소모하며 새 로그인으로 전달하지 않는다.
Future<String> waitForKakaoLogin(
  Future<String> Function() start, {
  Duration returnGrace = const Duration(seconds: 5),
  Duration timeout = const Duration(minutes: 5),
}) async {
  final pending = Completer<String>();
  final observer = _KakaoReturnObserver(pending, returnGrace);
  WidgetsBinding.instance.addObserver(observer);
  final timer = Timer(timeout, () {
    if (!pending.isCompleted) {
      pending.completeError(
        const KakaoLoginFailure('카카오 로그인 대기 시간이 초과되었습니다. 다시 시도해 주세요.'),
      );
    }
  });
  try {
    // SDK 요청을 실제로 취소할 수 없으므로 완료 여부를 검사해 늦은 결과를 무시한다.
    Future<String>.sync(start).then(
      (token) {
        if (!pending.isCompleted) pending.complete(token);
      },
      onError: (Object error, StackTrace stack) {
        if (!pending.isCompleted) pending.completeError(error, stack);
      },
    );
    return await pending.future;
  } finally {
    timer.cancel();
    observer.dispose();
    WidgetsBinding.instance.removeObserver(observer);
  }
}

class _KakaoReturnObserver extends WidgetsBindingObserver {
  _KakaoReturnObserver(this.pending, this.grace);
  final Completer<String> pending;
  final Duration grace;
  bool _leftApp = false;
  Timer? _returnTimer;

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.hidden) {
      _leftApp = true;
    }
    _returnTimer?.cancel();
    if (state == AppLifecycleState.resumed && _leftApp) {
      // 정상 복귀 시 SDK의 토큰 교환 결과가 먼저 도착할 시간을 준다.
      _returnTimer = Timer(grace, () {
        if (!pending.isCompleted) pending.completeError(KakaoLoginCancelled());
      });
    }
  }

  void dispose() => _returnTimer?.cancel();
}

final kakaoAccessTokenProvider = Provider<Future<String> Function()>(
  (ref) => KakaoLogin.accessToken,
);

final kakaoLoginHttpClientProvider = Provider<http.Client>((ref) {
  final client = http.Client();
  ref.onDispose(client.close);
  return client;
});

// 클라이언트에서 얻은 이메일을 믿지 않고, 서버가 카카오 API로 다시 검증한다.
final kakaoTokenExchangeProvider =
    Provider<Future<String> Function(String baseUrl, String token)>((ref) {
      final client = ref.watch(kakaoLoginHttpClientProvider);
      return (baseUrl, token) async {
        try {
          final response = await client
              .post(
                Uri.parse(
                  '${baseUrl.replaceAll(RegExp(r'/+$'), '')}/auth/kakao',
                ),
                headers: {'Content-Type': 'application/json'},
                body: jsonEncode({'access_token': token}),
              )
              .timeout(const Duration(seconds: 30));
          if (response.statusCode != 200) {
            throw KakaoLoginFailure(switch (response.statusCode) {
              401 => '카카오 인증이 만료되었습니다. 다시 로그인해 주세요.',
              403 => '사용이 중지된 계정입니다.',
              409 => '기존 계정이 있거나 이메일이 변경되었습니다. 기존 가입 방식으로 로그인해 주세요.',
              422 => '카카오계정의 인증된 이메일 제공 동의가 필요합니다.',
              _ => '카카오 로그인 서버 설정과 연결을 확인해 주세요.',
            });
          }
          final body =
              jsonDecode(utf8.decode(response.bodyBytes))
                  as Map<String, dynamic>;
          final customToken = body['custom_token'];
          if (customToken is! String || customToken.isEmpty) {
            throw const FormatException();
          }
          return customToken;
        } on KakaoLoginFailure {
          rethrow;
        } catch (_) {
          throw const KakaoLoginFailure('카카오 로그인 서버 연결을 확인해 주세요.');
        }
      };
    });

class KakaoLogin {
  static const nativeAppKey = String.fromEnvironment('KAKAO_NATIVE_APP_KEY');

  static void initialize() {
    if (!kIsWeb &&
        defaultTargetPlatform == TargetPlatform.android &&
        RegExp(r'^[a-fA-F0-9]{32}$').hasMatch(nativeAppKey)) {
      KakaoSdk.init(nativeAppKey: nativeAppKey, loggingEnabled: false);
    }
  }

  static Future<String> accessToken() async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) {
      throw const KakaoLoginFailure('카카오 로그인은 현재 Android에서 지원합니다.');
    }
    if (!RegExp(r'^[a-fA-F0-9]{32}$').hasMatch(nativeAppKey)) {
      throw const KakaoLoginFailure('실행 설정에 KAKAO_NATIVE_APP_KEY를 입력해 주세요.');
    }
    try {
      // 카카오톡 설치 여부와 관계없이 계정 로그인 화면에서 본인이 인증한다.
      final token = await UserApi.instance.loginWithKakaoAccount(
        prompts: [Prompt.login],
      );
      return token.accessToken;
    } on PlatformException catch (error) {
      if (error.code == 'CANCELED') throw KakaoLoginCancelled();
      throw const KakaoLoginFailure('카카오 Android 플랫폼 설정을 확인해 주세요.');
    } on KakaoClientException catch (error) {
      if (error.reason == ClientErrorCause.cancelled) {
        throw KakaoLoginCancelled();
      }
      throw const KakaoLoginFailure('카카오 로그인 설정을 확인해 주세요.');
    } on KakaoAuthException catch (error) {
      if (error.error == AuthErrorCause.accessDenied) {
        throw KakaoLoginCancelled();
      }
      throw const KakaoLoginFailure('카카오 로그인 동의 및 설정을 확인해 주세요.');
    } catch (_) {
      throw const KakaoLoginFailure('카카오 로그인에 실패했습니다. 다시 시도해 주세요.');
    }
  }
}
