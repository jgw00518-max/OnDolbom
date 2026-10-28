import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';
import 'package:ondolbom/model/memos/memo.dart';
import 'package:ondolbom/vm/family_room/family_context.dart';

export 'package:ondolbom/vm/family_room/family_context.dart'
    show apiBaseUrlProvider;

typedef MemoContext = FamilyContext;

// 로그인 프로필과 선택 공간을 목록·작성 화면에서 함께 사용한다.
final memoContextProvider = familyContextProvider;

final memoHttpClientProvider = Provider.autoDispose<http.Client>((ref) {
  final client = http.Client();
  ref.onDispose(client.close);
  return client;
});

const maxMemoImageBytes = 5 * 1024 * 1024;

// 선택기는 단일 사진만 반환하며 테스트에서는 이 provider를 대체한다.
final memoImagePickerProvider = Provider<Future<Uint8List?> Function()>((ref) {
  return () async {
    final file = await ImagePicker().pickImage(
      source: ImageSource.gallery,
      maxWidth: 2560,
      maxHeight: 2560,
      imageQuality: 85,
      requestFullMetadata: false,
    );
    if (file == null) return null;
    if (await file.length() > maxMemoImageBytes) {
      throw const MemoFailure('이미지는 5MB 이하로 첨부해 주세요.');
    }
    return file.readAsBytes();
  };
});

typedef MemoImageQuery = ({
  MemoContext context,
  String memoId,
  String authorId,
});

final memoImageProvider = FutureProvider.autoDispose
    .family<Uint8List, MemoImageQuery>((ref, query) async {
      final current = ref.watch(memoContextProvider);
      final client = ref.watch(memoHttpClientProvider);
      final baseUrl = ref
          .watch(apiBaseUrlProvider)
          .replaceFirst(RegExp(r'/+$'), '');
      final tokenLoader = ref.watch(apiTokenLoaderProvider);
      if (current != query.context) throw const MemoFailure('선택한 공간이 변경됐어요.');
      try {
        final token = await tokenLoader().timeout(const Duration(seconds: 15));
        if (token == null || token.isEmpty) {
          throw const MemoFailure('로그인이 필요해요.');
        }
        if (!ref.mounted || ref.read(memoContextProvider) != query.context) {
          throw const MemoFailure('선택한 공간이 변경됐어요.');
        }
        final response = await client
            .get(
              Uri.parse(
                '$baseUrl/memos/image/${Uri.encodeComponent(query.memoId)}',
              ).replace(
                queryParameters: {
                  'family_room_id': query.context.familyRoomId,
                  'author_user_id': query.authorId,
                },
              ),
              headers: {'Authorization': 'Bearer $token'},
            )
            .timeout(const Duration(seconds: 15));
        if (!ref.mounted || ref.read(memoContextProvider) != query.context) {
          throw const MemoFailure('선택한 공간이 변경됐어요.');
        }
        if (response.statusCode != 200) {
          throw const MemoFailure('사진을 불러오지 못했어요.');
        }
        return response.bodyBytes;
      } on TimeoutException {
        throw const MemoFailure('사진 응답이 지연되고 있어요.');
      } on http.ClientException {
        throw const MemoFailure('사진을 불러오지 못했어요. 연결 상태를 확인해 주세요.');
      }
    }, retry: (_, _) => null);

class MemoFailure implements Exception {
  const MemoFailure(this.message);
  final String message;
  @override
  String toString() => message;
}

class MemoLikeResult {
  const MemoLikeResult(this.likes);
  final int likes;
}

// 목록·상세의 요청 상태와 서버 응답을 같은 메모 식별자로 공유한다.
final memoLikeProvider = AsyncNotifierProvider.autoDispose
    .family<MemoLikeVm, MemoLikeResult?, MemoImageQuery>(
      MemoLikeVm.new,
      retry: (_, _) => null,
    );

class MemoLikeVm extends AsyncNotifier<MemoLikeResult?> {
  MemoLikeVm(this.query);
  final MemoImageQuery query;

  @override
  MemoLikeResult? build() => null;

  Future<void> like(Memo memo) async {
    if (state.isLoading || state.asData?.value != null || memo.isLiked) return;
    state = const AsyncLoading();
    try {
      final result = await ref
          .read(memoVmProvider(query.context).notifier)
          .likeMemo(memo);
      if (ref.mounted) state = AsyncData(result);
    } catch (_) {
      if (ref.mounted) state = const AsyncData(null);
      rethrow;
    }
  }
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
    int expected, {
    bool requireCurrentContext = false,
  }) async {
    final generation = _generation;
    try {
      final token = await _tokenLoader().timeout(const Duration(seconds: 15));
      if (token == null || token.isEmpty) {
        throw const MemoFailure('로그인이 필요해요. 로그인 상태를 확인해 주세요.');
      }
      if (!ref.mounted || generation != _generation) {
        throw const MemoFailure('로그인 상태가 변경되었습니다.');
      }
      if (requireCurrentContext && ref.read(memoContextProvider) != context) {
        throw const MemoFailure('선택한 공간이 변경됐어요. 목록으로 돌아가 주세요.');
      }
      final response = await send({
        'Authorization': 'Bearer $token',
        'Accept': 'application/json',
        'Content-Type': 'application/json; charset=utf-8',
      }).timeout(const Duration(seconds: 15));
      if (!ref.mounted || generation != _generation) {
        throw const MemoFailure('로그인 상태가 변경되었습니다.');
      }
      if (requireCurrentContext && ref.read(memoContextProvider) != context) {
        throw const MemoFailure('선택한 공간이 변경됐어요. 목록에서 처리 결과를 확인해 주세요.');
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

  Future<void> createMemo(String content, {Uint8List? image}) async {
    final text = content.trim();
    if (text.isEmpty || text.runes.length > 2000) {
      throw const MemoFailure('메모는 1~2,000자로 작성해 주세요.');
    }
    if (context.userId.isEmpty || context.familyRoomId.isEmpty) {
      throw const MemoFailure('사용자와 돌봄 공간을 먼저 선택해 주세요.');
    }
    _validateImage(image);
    await _request(
      (headers) => image != null
          ? _multipart('POST', 'insert-with-image', headers, text, image: image)
          : _client.post(
              _uri('insert'),
              headers: headers,
              body: jsonEncode({
                'family_room_id': context.familyRoomId,
                'memo_content': text,
              }),
            ),
      201,
      requireCurrentContext: image != null,
    );
    if (ref.mounted) ref.invalidateSelf();
  }

  void _checkCanManage(Memo memo) {
    if (ref.read(memoContextProvider) != context) {
      throw const MemoFailure('선택한 공간이 변경됐어요. 목록으로 돌아가 주세요.');
    }
    if (context.userId.isEmpty ||
        memo.userId != context.userId ||
        memo.familyRoomId != context.familyRoomId) {
      throw const MemoFailure('이 공간의 메모 작성자만 수정하거나 삭제할 수 있어요.');
    }
  }

  Future<void> updateMemo(
    Memo memo,
    String content, {
    Uint8List? image,
    bool removeImage = false,
  }) async {
    _checkCanManage(memo);
    final text = content.trim();
    if (text.isEmpty || text.runes.length > 2000) {
      throw const MemoFailure('메모는 1~2,000자로 작성해 주세요.');
    }
    _validateImage(image);
    if (image != null && removeImage) {
      throw const MemoFailure('사진 첨부와 제거를 동시에 할 수 없어요.');
    }
    await _request(
      (headers) => image != null || removeImage
          ? _multipart(
              'PATCH',
              'update-with-image/${Uri.encodeComponent(memo.memoId)}',
              headers,
              text,
              image: image,
              removeImage: removeImage,
            )
          : _client.patch(
              _uri('update/${Uri.encodeComponent(memo.memoId)}'),
              headers: headers,
              body: jsonEncode({
                'family_room_id': context.familyRoomId,
                'memo_content': text,
              }),
            ),
      200,
      requireCurrentContext: true,
    );
    if (ref.mounted) {
      ref.invalidate(
        memoImageProvider((
          context: context,
          memoId: memo.memoId,
          authorId: memo.userId,
        )),
      );
      ref.invalidateSelf();
    }
  }

  void _validateImage(Uint8List? image) {
    if (image != null && (image.isEmpty || image.length > maxMemoImageBytes)) {
      throw const MemoFailure('이미지는 5MB 이하의 파일로 첨부해 주세요.');
    }
  }

  Future<http.Response> _multipart(
    String method,
    String path,
    Map<String, String> headers,
    String content, {
    Uint8List? image,
    bool removeImage = false,
  }) async {
    final request = http.MultipartRequest(method, _uri(path))
      ..headers['Authorization'] = headers['Authorization']!
      ..fields['family_room_id'] = context.familyRoomId
      ..fields['memo_content'] = content;
    if (removeImage) request.fields['remove_image'] = 'true';
    if (image != null) {
      request.files.add(
        http.MultipartFile.fromBytes(
          'image',
          image,
          filename: 'memo-image.jpg',
        ),
      );
    }
    return http.Response.fromStream(await _client.send(request));
  }

  Future<void> deleteMemo(Memo memo) async {
    _checkCanManage(memo);
    await _request(
      (headers) => _client.delete(
        _uri('delete/${Uri.encodeComponent(memo.memoId)}', {
          'family_room_id': context.familyRoomId,
        }),
        headers: headers,
      ),
      200,
      requireCurrentContext: true,
    );
    if (ref.mounted) {
      ref.invalidate(
        memoImageProvider((
          context: context,
          memoId: memo.memoId,
          authorId: memo.userId,
        )),
      );
      ref.invalidateSelf();
    }
  }

  Future<MemoLikeResult> likeMemo(Memo memo) async {
    if (ref.read(memoContextProvider) != context ||
        context.userId.isEmpty ||
        context.familyRoomId.isEmpty ||
        memo.familyRoomId != context.familyRoomId) {
      throw const MemoFailure('선택한 공간과 로그인 상태를 확인해 주세요.');
    }
    final body = await _request(
      (headers) => _client.post(
        _uri('like/${Uri.encodeComponent(memo.memoId)}'),
        headers: headers,
        body: jsonEncode({
          'family_room_id': context.familyRoomId,
          'author_user_id': memo.userId,
        }),
      ),
      200,
      requireCurrentContext: true,
    );
    final likes = body['likes'];
    if (likes is! int || likes < 0 || body['is_liked'] != true) {
      throw const MemoFailure('좋아요 응답을 확인하지 못했어요. 다시 시도해 주세요.');
    }
    return MemoLikeResult(likes);
  }
}
