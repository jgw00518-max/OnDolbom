import 'package:ondolbom/vm/auth/auth_vm.dart';
import 'dart:convert';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:ondolbom/vm/chats/chat_vm.dart';
import 'package:ondolbom/vm/family_room/family_context.dart';

final chatNotificationsApiProvider = Provider<ChatNotificationsApi>((ref) {
  return ChatNotificationsApi(ref, ref.watch(apiTokenLoaderProvider));
});

/// 기존 채팅 인증·클라이언트를 공유하며 계정 전환 뒤 응답을 적용하지 않는다.
class ChatNotificationsApi {
  ChatNotificationsApi(this.ref, this.loadToken);
  final Ref ref;
  final Future<String?> Function() loadToken;
  Future<Map<String, dynamic>> request(
    String path, {
    Map<String, dynamic>? body,
  }) async {
    final token = await loadToken();
    if (token == null || token.isEmpty) throw const ChatFailure('로그인이 필요합니다.');
    final base = ref.read(apiBaseUrlProvider).replaceAll(RegExp(r'/+$'), '');
    final client = ref.read(chatHttpClientProvider);
    final headers = {
      'Authorization': 'Bearer $token',
      'Content-Type': 'application/json; charset=utf-8',
    };
    final response =
        await (body == null
                ? client.get(Uri.parse('$base/chats/$path'), headers: headers)
                : client.post(
                    Uri.parse('$base/chats/$path'),
                    headers: headers,
                    body: jsonEncode(body),
                  ))
            .timeout(const Duration(seconds: 15));
    if (!ref.mounted ||
        !identical(ref.read(apiTokenLoaderProvider), loadToken) ||
        await loadToken() == null) {
      throw const ChatFailure('로그인 상태가 변경되었습니다.');
    }
    if (response.statusCode != 200) {
      throw ChatFailure('채팅 알림 상태를 확인하지 못했습니다.', response.statusCode);
    }
    return jsonDecode(utf8.decode(response.bodyBytes)) as Map<String, dynamic>;
  }

  Future<int> markRead(String roomId, int seq) async {
    final result = await request(
      'read',
      body: {'family_room_id': roomId, 'chat_seq': seq},
    );
    return result['last_read_chat_seq'] as int;
  }
}

// 메뉴·앱 복귀·푸시 수신 때 무효화한다. 지속적인 전체 메시지 조회는 하지 않는다.
final chatUnreadProvider = FutureProvider.autoDispose<Map<String, int>>((
  ref,
) async {
  if (ref.watch(authUserProvider).asData?.value == null) return {};
  final loader = ref.watch(apiTokenLoaderProvider);
  if (await loader() == null) return {};
  final api = ref.watch(chatNotificationsApiProvider);
  final data = await api.request('unread');
  return (data['counts'] as Map<String, dynamic>).map(
    (key, value) => MapEntry(key, (value as num).toInt()),
  );
}, retry: (_, _) => null);

/// 표시 여부는 현재 화면이 직접 판정한다. 연결 중이라는 이유만으로 읽음 처리하지 않는다.
class ChatVisibility {
  final _views = <Object, bool Function(String, int)>{};
  void register(Object owner, bool Function(String, int) visible) =>
      _views[owner] = visible;
  void unregister(Object owner) => _views.remove(owner);
  bool isVisible(String roomId, int seq) =>
      _views.values.any((visible) => visible(roomId, seq));
}

final chatVisibilityProvider = Provider<ChatVisibility>(
  (ref) => ChatVisibility(),
);
