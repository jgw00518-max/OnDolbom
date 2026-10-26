import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';
import 'package:ondolbom/vm/chats/chat_vm.dart';
import 'package:ondolbom/vm/family_room/family_context.dart';

const maxChatImageBytes = 5 * 1024 * 1024;

final chatImagePickerProvider = Provider<Future<Uint8List?> Function()>((ref) {
  return () async {
    final file = await ImagePicker().pickImage(
      source: ImageSource.gallery,
      maxWidth: 2560,
      maxHeight: 2560,
      imageQuality: 85,
      requestFullMetadata: false,
    );
    if (file == null) return null;
    if (await file.length() > maxChatImageBytes) {
      throw const ChatFailure('이미지는 5MB 이하로 첨부해 주세요.');
    }
    return file.readAsBytes();
  };
});

typedef ChatImageQuery = ({FamilyContext context, int seq});

final chatImageProvider = FutureProvider.autoDispose
    .family<Uint8List, ChatImageQuery>((ref, query) async {
      final current = ref.watch(familyContextProvider);
      final client = ref.watch(chatHttpClientProvider);
      final base = Uri.parse(ref.watch(apiBaseUrlProvider));
      final tokenLoader = ref.watch(apiTokenLoaderProvider);
      if (current != query.context ||
          current.userId.isEmpty ||
          current.familyRoomId.isEmpty) {
        throw const ChatFailure('선택한 공간과 로그인 상태를 확인해 주세요.');
      }
      try {
        final token = await tokenLoader().timeout(const Duration(seconds: 15));
        if (!ref.mounted || ref.read(familyContextProvider) != query.context) {
          throw const ChatFailure('선택한 공간이 변경되었습니다.');
        }
        if (token == null || token.isEmpty) {
          throw const ChatFailure('다시 로그인해 주세요.', 401);
        }
        final response = await client
            .get(
              base.replace(
                pathSegments: [
                  ...base.pathSegments.where((part) => part.isNotEmpty),
                  'chats',
                  'messages',
                  '${query.seq}',
                  'image',
                ],
                queryParameters: {'family_room_id': query.context.familyRoomId},
                fragment: '',
              ),
              headers: {'Authorization': 'Bearer $token'},
            )
            .timeout(const Duration(seconds: 15));
        if (!ref.mounted || ref.read(familyContextProvider) != query.context) {
          throw const ChatFailure('선택한 공간이 변경되었습니다.');
        }
        if (response.statusCode != 200) {
          throw ChatFailure('사진을 불러오지 못했어요.', response.statusCode);
        }
        return response.bodyBytes;
      } on TimeoutException {
        throw const ChatFailure('사진 응답이 지연되고 있어요. 다시 시도해 주세요.');
      } on http.ClientException {
        throw const ChatFailure('사진을 불러오지 못했어요. 연결 상태를 확인해 주세요.');
      }
    }, retry: (_, _) => null);
