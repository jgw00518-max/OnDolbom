import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_web_auth_2/flutter_web_auth_2.dart';
import 'package:http/http.dart' as http;
import 'package:ondolbom/model/auth/kakao_login.dart';

class NaverLoginCancelled implements Exception {}

class NaverLoginFailure implements Exception {
  const NaverLoginFailure(this.message);
  final String message;
}

final naverBrowserProvider = Provider<Future<String> Function(String)>((ref) {
  return (url) async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) {
      throw const NaverLoginFailure('네이버 로그인은 현재 Android에서 지원합니다.');
    }
    return FlutterWebAuth2.authenticate(
      url: url,
      callbackUrlScheme: 'ondolbomnaver',
    );
  };
});

final naverHttpClientProvider = Provider<http.Client>((ref) {
  final client = http.Client();
  ref.onDispose(client.close);
  return client;
});

// 공개 Client ID도 서버에서 읽으므로 팀원은 앱용 네이버 키를 따로 설정하지 않는다.
final naverCustomTokenProvider = Provider<Future<String> Function(String)>((
  ref,
) {
  final client = ref.watch(naverHttpClientProvider);
  final browser = ref.watch(naverBrowserProvider);
  return (baseUrl) => NaverLogin.authenticate(baseUrl, client, browser);
});

class NaverLogin {
  static Future<Map<String, dynamic>> _post(
    http.Client client,
    String url,
    Map<String, String> payload,
  ) async {
    final response = await client
        .post(
          Uri.parse(url),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode(payload),
        )
        .timeout(const Duration(seconds: 30));
    if (response.statusCode != 200) {
      throw NaverLoginFailure(switch (response.statusCode) {
        400 || 401 => '네이버 로그인 요청이 만료되었거나 일치하지 않습니다. 다시 시도해 주세요.',
        403 => '사용이 중지된 계정입니다.',
        409 => '기존 계정이 있거나 연락처 이메일이 변경되었습니다. 기존 가입 방식으로 로그인해 주세요.',
        422 => '네이버 연락처 이메일 제공 동의가 필요합니다.',
        _ => '네이버 로그인 서버 설정과 연결을 확인해 주세요.',
      });
    }
    return jsonDecode(utf8.decode(response.bodyBytes)) as Map<String, dynamic>;
  }

  static Future<String> authenticate(
    String baseUrl,
    http.Client client,
    Future<String> Function(String) browser,
  ) async {
    final base = baseUrl.replaceAll(RegExp(r'/+$'), '');
    // 이 앱 요청만 가진 난수. URL에는 해시만 포함하고 원문은 서버 교환 요청에만 보낸다.
    final random = Random.secure();
    final verifier = base64UrlEncode(
      List.generate(32, (_) => random.nextInt(256)),
    ).replaceAll('=', '');
    try {
      final start = await _post(client, '$base/auth/naver/start', {
        'challenge': sha256.convert(utf8.encode(verifier)).toString(),
      });
      final state = start['state'] as String;
      final authorizationUrl = start['authorization_url'] as String;
      final authorization = Uri.parse(authorizationUrl);
      if (authorization.scheme != 'https' ||
          authorization.host != 'nid.naver.com' ||
          authorization.path != '/oauth2.0/authorize' ||
          authorization.queryParameters['state'] != state) {
        throw const FormatException();
      }
      // 카카오에서 검증한 브라우저 복귀·늦은 응답 방어를 재사용한다.
      final result = await waitForKakaoLogin(() => browser(authorizationUrl));
      final callback = Uri.parse(result);
      if (callback.scheme != 'ondolbomnaver' ||
          callback.host != 'oauth' ||
          callback.queryParameters['state'] != state) {
        throw const NaverLoginFailure('네이버 로그인 응답이 요청과 일치하지 않습니다.');
      }
      if (callback.queryParameters.containsKey('error')) {
        throw NaverLoginCancelled();
      }
      final code = callback.queryParameters['code'];
      if (code == null || code.isEmpty) throw const FormatException();
      final exchange = await _post(client, '$base/auth/naver/exchange', {
        'state': state,
        'code': code,
        'verifier': verifier,
      });
      final token = exchange['custom_token'];
      if (token is! String || token.isEmpty) throw const FormatException();
      return token;
    } on KakaoLoginCancelled {
      throw NaverLoginCancelled();
    } on KakaoLoginFailure {
      throw const NaverLoginFailure('네이버 로그인 대기 시간이 초과되었습니다. 다시 시도해 주세요.');
    } on PlatformException catch (error) {
      if (error.code == 'CANCELED' || error.code == 'CANCELLED') {
        throw NaverLoginCancelled();
      }
      throw const NaverLoginFailure('네이버 브라우저 로그인에 실패했습니다. 다시 시도해 주세요.');
    } on NaverLoginCancelled {
      rethrow;
    } on NaverLoginFailure {
      rethrow;
    } catch (_) {
      throw const NaverLoginFailure('네이버 로그인 서버 연결 또는 설정을 확인해 주세요.');
    }
  }
}
