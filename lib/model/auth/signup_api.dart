import 'dart:convert';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:ondolbom/vm/auth/user_profile_vm.dart' show apiBaseUrlProvider;

class SignupFailure implements Exception {
  const SignupFailure(this.message);
  final String message;
  @override
  String toString() => message;
}

final signupApiProvider = Provider<SignupApi>((ref) {
  final client = http.Client();
  ref.onDispose(client.close);
  return SignupApi(ref.watch(apiBaseUrlProvider), client);
});

class SignupApi {
  SignupApi(this.baseUrl, this.client);
  final String baseUrl;
  final http.Client client;

  Future<Map<String, dynamic>> post(
    String step,
    Map<String, String> payload,
  ) async {
    try {
      final response = await client
          .post(
            Uri.parse(
              '${baseUrl.replaceAll(RegExp(r'/+$'), '')}/auth/signup/$step',
            ),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode(payload),
          )
          .timeout(const Duration(seconds: 30));
      if (response.statusCode != 200) {
        throw SignupFailure(switch (response.statusCode) {
          400 => '인증 정보가 틀렸거나 만료되었습니다. 인증번호를 다시 요청해 주세요.',
          409 => '이미 가입된 이메일입니다. 기존 가입 방식으로 로그인해 주세요.',
          429 => '발송 요청이 많습니다. 잠시 후 다시 시도해 주세요.',
          422 => '입력값을 확인해 주세요. 비밀번호는 6~128자입니다.',
          _ => '가입 요청 결과를 확인하지 못했습니다. 서버의 메일 설정과 연결을 확인해 주세요.',
        });
      }
      return jsonDecode(utf8.decode(response.bodyBytes))
          as Map<String, dynamic>;
    } on SignupFailure {
      rethrow;
    } catch (_) {
      throw const SignupFailure(
        '서버 연결을 확인해 주세요. 가입 요청 중이었다면 로그인 확인 후 다시 시도해 주세요.',
      );
    }
  }
}
