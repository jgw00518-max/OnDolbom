import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:ondolbom/model/family/family_room.dart';
import 'package:ondolbom/model/family/participate.dart';
import 'package:ondolbom/vm/family_room_state.dart';

final familyRoomProvider =
    NotifierProvider<FamilyRoomNotifier, FamilyRoomState>(
      FamilyRoomNotifier.new,
    );

class FamilyRoomNotifier extends Notifier<FamilyRoomState> {
  // 실행할 때 서버 주소를 전달한다.
  static const String baseUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: 'http://10.0.2.2:8000',
  );

  // 로그인 연결 전까지만 사용하는 테스트 사용자이다.
  static const String devUserId = String.fromEnvironment(
    'DEV_USER_ID',
    defaultValue: 'sook',
  );

  @override
  FamilyRoomState build() {
    return const FamilyRoomState();
  }

  Future<void> fetchRooms() async {
    if (state.isLoading) {
      return;
    }

    state = state.copyWith(
      isLoading: true,
      clearError: true,
    );

    try {
      final response = await http.get(
        Uri.parse('$baseUrl/family-room'),
        headers: {
          'x-dev-user-id': devUserId,
        },
      ).timeout(const Duration(seconds: 10));

      if (response.statusCode != 200) {
        throw Exception(
          '공간 조회에 실패했습니다. (${response.statusCode})',
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

      // 기존 선택이 유효하면 유지한다.
      String? selectedId = state.selectedRoomId;

      final selectionExists = rooms.any(
        (room) => room.familyRoomId == selectedId,
      );

      if (!selectionExists) {
        selectedId = null;
      }

      // 공간이 한 개면 자동 선택한다.
      if (rooms.length == 1) {
        selectedId = rooms.first.familyRoomId;
      }

      state = FamilyRoomState(
        rooms: rooms,
        participations: participations,
        selectedRoomId: selectedId,
      );
    } catch (error) {
      // 조회 실패 시 이전 공간의 내용을 계속 표시하지 않는다.
      state = FamilyRoomState(
        errorMessage: error.toString(),
      );
    }
  }

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

  // 대상자 정보를 보내 공간과 주보호자 참여 정보를 생성한다.
Future<bool> createRoom({
  required String name,
  String? birthDate,
  String? address,
  String? notes,
}) async {
  if (state.isLoading) {
    return false;
  }

  state = state.copyWith(
    isLoading: true,
    clearError: true,
  );

  try {
    final response = await http.post(
      Uri.parse('$baseUrl/family-room'),
      headers: {
        'Content-Type': 'application/json',
        'x-dev-user-id': devUserId,
      },
      body: jsonEncode({
        'care_recipient_name': name,
        'birth_date': birthDate,
        'care_address': address,
        'special_notes': notes,
      }),
    ).timeout(const Duration(seconds: 10));

    if (response.statusCode != 201) {
      throw Exception(
        '공간 생성에 실패했습니다. (${response.statusCode})',
      );
    }

    state = state.copyWith(isLoading: false);

    return true;
  } catch (error) {
    state = state.copyWith(
      isLoading: false,
      errorMessage: error.toString(),
    );

    return false;
  }
}
}