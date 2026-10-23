import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:ondolbom/model/family/family_room.dart';
import 'package:ondolbom/model/family/participate.dart';
import 'package:ondolbom/vm/auth/auth_vm.dart';
import 'package:ondolbom/vm/auth/user_profile_vm.dart';
import 'package:ondolbom/vm/family_room_state.dart';

final familyRoomProvider =
    NotifierProvider<FamilyRoomNotifier, FamilyRoomState>(
      FamilyRoomNotifier.new,
    );

class FamilyRoomNotifier extends Notifier<FamilyRoomState> {
  // 계정 변경 전의 요청 결과를 구분한다.
  Object sessionKey = Object();

  // A 담당자가 만든 공통 서버 주소를 사용한다.
  String get baseUrl {
    return ref
        .read(apiBaseUrlProvider)
        .replaceAll(RegExp(r'/+$'), '');
  }

  @override
  FamilyRoomState build() {
    // 로그인 계정이 변경되면 공간 상태를 초기화한다.
    ref.watch(authUserProvider);
    sessionKey = Object();

    return const FamilyRoomState();
  }

  // ----- function -----

  // 로그인한 사용자의 Firebase ID 토큰을 가져온다.
  Future<String> getLoginToken() async {
    final user = ref.read(firebaseAuthProvider).currentUser;

    if (user == null) {
      throw Exception('로그인이 필요합니다.');
    }

    final token = await user.getIdToken();

    if (token == null || token.isEmpty) {
      throw Exception('로그인 정보를 가져오지 못했습니다.');
    }

    return token;
  }

  // 요청 중 계정이 변경되거나 상태가 초기화됐는지 확인한다.
  bool isCurrentRequest(Object requestKey, String? requestUid) {
    return ref.mounted &&
        identical(sessionKey, requestKey) &&
        ref.read(firebaseAuthProvider).currentUser?.uid ==
            requestUid;
  }

  // 서버가 보내는 오류 안내를 가져온다.
  String getErrorMessage(
    http.Response response,
    String defaultMessage,
  ) {
    try {
      final body = jsonDecode(utf8.decode(response.bodyBytes));

      if (body is Map<String, dynamic> &&
          body['detail'] is String) {
        return body['detail'] as String;
      }
    } catch (_) {
      // JSON 응답이 아니면 기본 안내를 사용한다.
    }

    return '$defaultMessage (${response.statusCode})';
  }

  // 현재 사용자가 참여 중인 가족 공간을 조회한다.
  Future<void> fetchRooms() async {
    if (state.isLoading) {
      return;
    }

    final requestKey = sessionKey;
    final requestUid =
        ref.read(firebaseAuthProvider).currentUser?.uid;

    state = state.copyWith(
      isLoading: true,
      clearError: true,
    );

    try {
      final token = await getLoginToken();

      if (!isCurrentRequest(requestKey, requestUid)) {
        return;
      }

      final response = await http.get(
        Uri.parse('$baseUrl/family-room'),
        headers: {
          'Authorization': 'Bearer $token',
        },
      ).timeout(const Duration(seconds: 10));

      if (!isCurrentRequest(requestKey, requestUid)) {
        return;
      }

      if (response.statusCode != 200) {
        throw Exception(
          getErrorMessage(
            response,
            '공간 목록을 불러오지 못했습니다.',
          ),
        );
      }

      final body =
          jsonDecode(utf8.decode(response.bodyBytes))
              as Map<String, dynamic>;

      final results = body['results'] as List<dynamic>;

      final rooms = <FamilyRoom>[];
      final participations = <String, Participate>{};

      for (final item in results) {
        final row = item as Map<String, dynamic>;

        final room = FamilyRoom.fromJson(
          row['family_room'] as Map<String, dynamic>,
        );

        final participation = Participate.fromJson(
          row['participate'] as Map<String, dynamic>,
        );

        rooms.add(room);
        participations[room.familyRoomId] = participation;
      }

      // 기존에 선택한 공간이 목록에 있으면 선택을 유지한다.
      String? selectedId = state.selectedRoomId;

      final selectionExists = rooms.any(
        (room) => room.familyRoomId == selectedId,
      );

      if (!selectionExists) {
        selectedId = null;
      }

      // 참여 공간이 한 개면 자동 선택한다.
      if (rooms.length == 1) {
        selectedId = rooms.first.familyRoomId;
      }

      state = FamilyRoomState(
        rooms: rooms,
        participations: participations,
        selectedRoomId: selectedId,
      );
    } catch (error) {
      if (!isCurrentRequest(requestKey, requestUid)) {
        return;
      }

      state = FamilyRoomState(
        errorMessage: error.toString(),
      );
    }
  }

  // 현재 사용할 가족 공간을 선택한다.
  void selectRoom(String familyRoomId) {
    final exists = state.rooms.any(
      (room) => room.familyRoomId == familyRoomId,
    );

    if (!exists) {
      return;
    }

    state = state.copyWith(
      selectedRoomId: familyRoomId,
      clearError: true,
    );
  }

  // 대상자를 등록하고 가족 공간을 생성한다.
  Future<bool> createRoom({
    required String name,
    String? birthDate,
    String? address,
    String? notes,
  }) async {
    if (state.isLoading) {
      return false;
    }

    final requestKey = sessionKey;
    final requestUid =
        ref.read(firebaseAuthProvider).currentUser?.uid;

    state = state.copyWith(
      isLoading: true,
      clearError: true,
    );

    try {
      final token = await getLoginToken();

      if (!isCurrentRequest(requestKey, requestUid)) {
        return false;
      }

      final response = await http.post(
        Uri.parse('$baseUrl/family-room'),
        headers: {
          'Content-Type': 'application/json; charset=utf-8',
          'Authorization': 'Bearer $token',
        },
        body: jsonEncode({
          'care_recipient_name': name,
          'birth_date': birthDate,
          'care_address': address,
          'special_notes': notes,
        }),
      ).timeout(const Duration(seconds: 10));

      if (!isCurrentRequest(requestKey, requestUid)) {
        return false;
      }

      if (response.statusCode != 201) {
        throw Exception(
          getErrorMessage(
            response,
            '가족 공간을 생성하지 못했습니다.',
          ),
        );
      }

      // 목록 재조회는 입력 화면에서 돌아온 뒤 실행한다.
      state = state.copyWith(
        isLoading: false,
        clearError: true,
      );

      return true;
    } catch (error) {
      if (!isCurrentRequest(requestKey, requestUid)) {
        return false;
      }

      state = state.copyWith(
        isLoading: false,
        errorMessage: error.toString(),
      );

      return false;
    }
  }
} // class