import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

typedef FamilyContext = ({String familyRoomId, String userId, String roomName});

// 로그인·공간 선택 기능이 준비되면 두 기능이 함께 사용하는 이 상태에 연결한다.
final familyContextProvider = Provider<FamilyContext>(
  (ref) => (
    familyRoomId: const String.fromEnvironment('FAMILY_ROOM_ID'),
    userId: const String.fromEnvironment('USER_ID'),
    roomName: const String.fromEnvironment(
      'FAMILY_ROOM_NAME',
      defaultValue: '가족 돌봄 공간',
    ),
  ),
);

final apiBaseUrlProvider = Provider<String>((ref) {
  const configured = String.fromEnvironment('API_BASE_URL');
  if (configured.isNotEmpty) return configured;
  return !kIsWeb && defaultTargetPlatform == TargetPlatform.android
      ? 'http://10.0.2.2:8000'
      : 'http://127.0.0.1:8000';
});

// 로그인 담당 코드에서 호출 시점의 유효한 토큰을 반환하도록 연결한다.
// 실행 옵션의 USER_ID를 인증 토큰으로 사용하지 않는다.
final apiTokenLoaderProvider = Provider<Future<String?> Function()>(
  (ref) =>
      () async => null,
);
