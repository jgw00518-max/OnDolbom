import 'dart:async';
import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:ondolbom/model/memos/memo.dart';
import 'package:ondolbom/vm/family_context.dart';

export 'package:ondolbom/vm/family_context.dart' show apiBaseUrlProvider;

typedef MemoContext = FamilyContext;

// 로그인 프로필과 선택 공간을 목록·작성 화면에서 함께 사용한다.
final memoContextProvider = familyContextProvider;

final memoHttpClientProvider = Provider.autoDispose<http.Client>((ref) {
  final client = http.Client();
  ref.onDispose(client.close);
  return client;
});

class MemoFailure implements Exception {
  const MemoFailure(this.message);
  final String message;
  @override
  String toString() => message;
}

class MemoFeed {
  const MemoFeed(
    this.items, {
    required this.hasMore,
    this.loadingMore = false,
    this.nextOffset = 0,
  });
  final List<Memo> items;
  final bool hasMore;
  final bool loadingMore;
  final int nextOffset;
}

final memoVmProvider = AsyncNotifierProvider.autoDispose
    .family<MemoVm, MemoFeed, MemoContext>(MemoVm.new, retry: (_, _) => null);

class MemoVm extends AsyncNotifier<MemoFeed> {
  MemoVm(this.context);
  final MemoContext context;
  static const pageSize = 20;
  late http.Client _client;
  late String _baseUrl;
  late Future<String?> Function() _tokenLoader;
  int _generation = 0;

  @override
  Future<MemoFeed> build() async {
    _generation++;
    _client = ref.watch(memoHttpClientProvider);
    _baseUrl = ref.watch(apiBaseUrlProvider);
    _tokenLoader = ref.watch(apiTokenLoaderProvider);
    if (context.familyRoomId.isEmpty) return const MemoFeed([], hasMore: false);
    final items = await _fetch(0);
    return MemoFeed(
      items,
      hasMore: items.length == pageSize,
      nextOffset: items.length,
    );
  }

  Uri _uri(String path, [Map<String, String>? query]) => Uri.parse(
    '${_baseUrl.replaceFirst(RegExp(r'/+$'), '')}/memos/$path',
  ).replace(queryParameters: query);

  Future<Map<String, dynamic>> _request(
    Future<http.Response> Function(Map<String, String> headers) send,
    int expected,
  ) async {
    final generation = _generation;
    try {
      final token = await _tokenLoader().timeout(const Duration(seconds: 15));
      if (token == null || token.isEmpty) {
        throw const MemoFailure('로그인이 필요해요. 로그인 상태를 확인해 주세요.');
      }
      if (!ref.mounted || generation != _generation) {
        throw const MemoFailure('로그인 상태가 변경되었습니다.');
      }
      final response = await send({
        'Authorization': 'Bearer $token',
        'Accept': 'application/json',
        'Content-Type': 'application/json; charset=utf-8',
      }).timeout(const Duration(seconds: 15));
      if (!ref.mounted || generation != _generation) {
        throw const MemoFailure('로그인 상태가 변경되었습니다.');
      }
      if (response.statusCode == 401) {
        throw const MemoFailure('로그인이 필요해요. 로그인 상태를 확인해 주세요.');
      }
      if (response.statusCode == 403) {
        throw const MemoFailure('이 공간의 메모에 접근할 수 없어요.');
      }
      final body =
          jsonDecode(utf8.decode(response.bodyBytes)) as Map<String, dynamic>;
      if (response.statusCode != expected) {
        final detail = body['detail'];
        throw MemoFailure(
          detail is String ? detail : '요청을 처리하지 못했어요. 입력 내용을 확인해 주세요.',
        );
      }
      return body;
    } on TimeoutException {
      throw const MemoFailure('응답이 지연되고 있어요. 잠시 후 다시 시도해 주세요.');
    } on http.ClientException {
      throw const MemoFailure('서버에 연결할 수 없어요. 연결 상태를 확인해 주세요.');
    } on FormatException {
      throw const MemoFailure('서버 응답을 읽지 못했어요. 잠시 후 다시 시도해 주세요.');
    }
  }

  Future<List<Memo>> _fetch(int offset) async {
    final body = await _request(
      (headers) => _client.get(
        _uri('select', {
          'family_room_id': context.familyRoomId,
          'limit': '$pageSize',
          'offset': '$offset',
        }),
        headers: headers,
      ),
      200,
    );
    return (body['results'] as List<dynamic>)
        .map((item) => Memo.fromJson(item as Map<String, dynamic>))
        .toList();
  }

  Future<void> loadMore() async {
    final previous = state.asData?.value;
    if (previous == null || previous.loadingMore || !previous.hasMore) return;
    final generation = _generation;
    state = AsyncData(
      MemoFeed(
        previous.items,
        hasMore: true,
        loadingMore: true,
        nextOffset: previous.nextOffset,
      ),
    );
    try {
      final next = await _fetch(previous.nextOffset);
      if (!ref.mounted || generation != _generation) return;
      // 새 메모가 추가되어 offset이 이동한 경우 중복 표시를 피한다.
      final byId = {
        for (final m in [...previous.items, ...next])
          (m.memoId, m.familyRoomId, m.userId): m,
      };
      state = AsyncData(
        MemoFeed(
          byId.values.toList(),
          hasMore: next.length == pageSize,
          nextOffset: previous.nextOffset + next.length,
        ),
      );
    } catch (_) {
      if (ref.mounted && generation == _generation) state = AsyncData(previous);
      rethrow;
    }
  }

  Future<void> createMemo(String content) async {
    final text = content.trim();
    if (text.isEmpty || text.runes.length > 10000) {
      throw const MemoFailure('메모는 1~10,000자로 작성해 주세요.');
    }
    if (context.userId.isEmpty || context.familyRoomId.isEmpty) {
      throw const MemoFailure('사용자와 돌봄 공간을 먼저 선택해 주세요.');
    }
    await _request(
      (headers) => _client.post(
        _uri('insert'),
        headers: headers,
        body: jsonEncode({
          'family_room_id': context.familyRoomId,
          'memo_content': text,
        }),
      ),
      201,
    );
    if (ref.mounted) ref.invalidateSelf();
  }
}
