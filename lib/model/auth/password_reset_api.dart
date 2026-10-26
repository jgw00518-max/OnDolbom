import 'dart:convert';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:ondolbom/vm/auth/user_profile_vm.dart' show apiBaseUrlProvider;

class PasswordResetFailure implements Exception {
  const PasswordResetFailure(this.message);
  final String message;
  @override
  String toString() => message;
}

final passwordResetApiProvider = Provider<PasswordResetApi>((ref) {
  final client = http.Client();
  ref.onDispose(client.close);
  return PasswordResetApi(ref.watch(apiBaseUrlProvider), client);
});

class PasswordResetApi {
  PasswordResetApi(this.baseUrl, this.client);
  final String baseUrl;
  final http.Client client;

  Future<Map<String, dynamic>> post(
    String step,
    Map<String, String> data,
  ) async {
    try {
      final response = await client
          .post(
            Uri.parse(
              '${baseUrl.replaceAll(RegExp(r'/+$'), '')}/auth/password-reset/$step',
            ),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode(data),
          )
          .timeout(const Duration(seconds: 30));
      if (response.statusCode != 200) {
        // 서버 예외 원문과 입력한 비밀번호·코드를 화면이나 로그에 노출하지 않는다.
        throw PasswordResetFailure(switch (response.statusCode) {
          400 => '인증번호가 틀렸거나 인증이 만료되었습니다. 다시 요청해 주세요.',
          429 => '발송 요청이 많습니다. 잠시 후 다시 시도해 주세요.',
          422 => '입력값을 확인해 주세요. 비밀번호는 6~128자입니다.',
          _ => '요청 결과를 확인하지 못했습니다. 서버의 메일 설정과 연결을 확인해 주세요.',
        });
      }
      return jsonDecode(utf8.decode(response.bodyBytes))
          as Map<String, dynamic>;
    } on PasswordResetFailure {
      rethrow;
    } catch (_) {
      throw const PasswordResetFailure(
        '서버 연결을 확인해 주세요. 변경 요청 중이었다면 로그인 확인 후 다시 시도해 주세요.',
      );
    }
  }
}
