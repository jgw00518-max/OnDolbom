import 'dart:async';
import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:ondolbom/model/family/family_room.dart';
import 'package:ondolbom/model/family/participate.dart';
import 'package:ondolbom/vm/auth/auth_vm.dart';
import 'package:ondolbom/vm/auth/user_profile_vm.dart';
import 'package:ondolbom/vm/family_room/family_room_state.dart';

final familyRoomProvider =
    NotifierProvider<FamilyRoomNotifier, FamilyRoomState>(
      FamilyRoomNotifier.new,
    );

final familyRoomHttpClientProvider = Provider<http.Client>((ref) {
  final client = http.Client();
  ref.onDispose(client.close);
  return client;
});

class FamilyRoomDeleteFailure implements Exception {
  const FamilyRoomDeleteFailure(this.message);
  final String message;
}

class FamilyRoomMembershipFailure implements Exception {
  const FamilyRoomMembershipFailure(this.message);
  final String message;
}

class RepresentativeTransferFailure implements Exception {
  const RepresentativeTransferFailure(this.message);
  final String message;
}

class FamilyRoomNotifier extends Notifier<FamilyRoomState> {
  // 계정 변경 전의 요청 결과를 구분한다.
  Object sessionKey = Object();

  // A 담당자가 만든 공통 서버 주소를 사용한다.
  String get baseUrl {
    return ref.read(apiBaseUrlProvider).replaceAll(RegExp(r'/+$'), '');
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
        ref.read(firebaseAuthProvider).currentUser?.uid == requestUid;
  }

  // 서버가 보내는 오류 안내를 가져온다.
  String getErrorMessage(http.Response response, String defaultMessage) {
    try {
      final body = jsonDecode(utf8.decode(response.bodyBytes));

      if (body is Map<String, dynamic> && body['detail'] is String) {
        return body['detail'] as String;
      }
    } catch (_) {
      // JSON 응답이 아니면 기본 안내를 사용한다.
    }

    return '$defaultMessage (${response.statusCode})';
  }

  // 현재 사용자가 참여 중인 돌봄 공간을 조회한다.
  Future<void> fetchRooms() => _fetchRooms();

  // 역할 변경이 확정된 뒤 재조회 실패로 확정된 로컬 상태를 지우지 않는다.
  Future<void> refreshRoomsPreservingState() =>
      _fetchRooms(preserveOnError: true);

  Future<void> _fetchRooms({bool preserveOnError = false}) async {
    if (state.isLoading) {
      return;
    }

    final requestKey = sessionKey;
    final requestUid = ref.read(firebaseAuthProvider).currentUser?.uid;

    state = state.copyWith(isLoading: true, clearError: true);

    try {
      final token = await getLoginToken();

      if (!isCurrentRequest(requestKey, requestUid)) {
        return;
      }

      final response = await ref
          .read(familyRoomHttpClientProvider)
          .get(
            Uri.parse('$baseUrl/family-room'),
            headers: {'Authorization': 'Bearer $token'},
          )
          .timeout(const Duration(seconds: 10));

      if (!isCurrentRequest(requestKey, requestUid)) {
        return;
      }

      if (response.statusCode != 200) {
        throw Exception(getErrorMessage(response, '공간 목록을 불러오지 못했습니다.'));
      }

      final body =
          jsonDecode(utf8.decode(response.bodyBytes)) as Map<String, dynamic>;

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

      state = preserveOnError
          ? state.copyWith(isLoading: false, errorMessage: error.toString())
          : FamilyRoomState(errorMessage: error.toString());
    }
  }

  // 현재 사용할 돌봄 공간을 선택한다.
  void selectRoom(String familyRoomId) {
    final exists = state.rooms.any((room) => room.familyRoomId == familyRoomId);

    if (!exists) {
      return;
    }

    state = state.copyWith(selectedRoomId: familyRoomId, clearError: true);
  }

  Future<void> transferRepresentative({
    required String familyRoomId,
    required String targetUserId,
  }) async {
    if (state.isLoading) {
      throw const RepresentativeTransferFailure(
        '다른 요청을 처리 중이에요. 잠시 후 다시 시도해 주세요.',
      );
    }
    final requestKey = sessionKey;
    final uid = ref.read(firebaseAuthProvider).currentUser?.uid;
    final actor = state.selectedParticipation;
    void checkTarget() {
      final current = state.selectedParticipation;
      if (uid == null ||
          !isCurrentRequest(requestKey, uid) ||
          state.selectedRoomId != familyRoomId ||
          current?.participateSeq != actor?.participateSeq ||
          current?.userId != actor?.userId ||
          current?.isRepresentative != true ||
          current?.isActive != true) {
        throw const RepresentativeTransferFailure(
          '계정·공간 또는 권한이 변경됐어요. 목록을 다시 확인해 주세요.',
        );
      }
      if (targetUserId.trim().isEmpty ||
          targetUserId != targetUserId.trim() ||
          targetUserId == actor?.userId) {
        throw const RepresentativeTransferFailure('다른 가족을 선택해 주세요.');
      }
    }

    checkTarget();
    state = state.copyWith(isLoading: true, clearError: true);
    try {
      final token = await getLoginToken().timeout(const Duration(seconds: 15));
      checkTarget();
      final response = await ref
          .read(familyRoomHttpClientProvider)
          .post(
            Uri.parse(
              '$baseUrl/family-room/${Uri.encodeComponent(familyRoomId)}/transfer-representative',
            ),
            headers: {
              'Authorization': 'Bearer $token',
              'Content-Type': 'application/json; charset=utf-8',
            },
            body: jsonEncode({'target_user_id': targetUserId}),
          )
          .timeout(const Duration(seconds: 30));
      checkTarget();
      if (response.statusCode != 200) {
        throw RepresentativeTransferFailure(
          getErrorMessage(response, '주보호자를 이전하지 못했습니다.'),
        );
      }
      final body = jsonDecode(utf8.decode(response.bodyBytes));
      if (body is! Map ||
          body['result'] != 'OK' ||
          body['family_room_id'] != familyRoomId ||
          body['previous_representative_user_id'] != actor!.userId ||
          body['representative_user_id'] != targetUserId) {
        throw const RepresentativeTransferFailure(
          '이전 결과를 확인하지 못했습니다. 공간·가족 목록을 새로고침해 주세요.',
        );
      }
      // 서버 재조회가 실패해도 이미 넘긴 관리 권한을 화면에서 다시 사용하지 않게 한다.
      final participations = Map<String, Participate>.of(state.participations);
      participations[familyRoomId] = Participate(
        participateSeq: actor.participateSeq,
        userId: actor.userId,
        familyRoomId: actor.familyRoomId,
        isRepresentative: false,
        joinedAt: actor.joinedAt,
        leftAt: actor.leftAt,
      );
      state = state.copyWith(participations: participations);
    } on RepresentativeTransferFailure {
      rethrow;
    } on TimeoutException {
      throw const RepresentativeTransferFailure(
        '이전 결과 확인이 지연됩니다. 공간·가족 목록을 새로고침해 처리 여부를 확인해 주세요.',
      );
    } catch (_) {
      throw const RepresentativeTransferFailure(
        '이전 결과를 확인하지 못했습니다. 연결 상태와 공간·가족 목록을 확인해 주세요.',
      );
    } finally {
      if (isCurrentRequest(requestKey, uid)) {
        state = state.copyWith(isLoading: false);
      }
    }
  }

  // 서버 권한을 최종 기준으로 하며 계정·선택 공간이 바뀐 응답은 적용하지 않는다.
  Future<void> endMembership({
    required String familyRoomId,
    int? participateSeq,
  }) async {
    if (state.isLoading) {
      throw const FamilyRoomMembershipFailure(
        '다른 요청을 처리 중이에요. 잠시 후 다시 시도해 주세요.',
      );
    }
    final requestKey = sessionKey;
    final uid = ref.read(firebaseAuthProvider).currentUser?.uid;
    final memberId = state.selectedParticipation?.userId;
    void checkTarget() {
      final member = state.selectedParticipation;
      if (uid == null ||
          !isCurrentRequest(requestKey, uid) ||
          state.selectedRoomId != familyRoomId ||
          member?.isActive != true) {
        throw const FamilyRoomMembershipFailure(
          '계정·공간이 변경됐어요. 목록을 다시 확인해 주세요.',
        );
      }
      if (participateSeq == null && member!.isRepresentative) {
        throw const FamilyRoomMembershipFailure('주보호자는 이전 후 공간에서 나갈 수 있습니다.');
      }
      if (participateSeq != null && member!.isRepresentative != true) {
        throw const FamilyRoomMembershipFailure('현재 주보호자만 가족을 강퇴할 수 있습니다.');
      }
    }

    checkTarget();
    state = state.copyWith(isLoading: true, clearError: true);
    try {
      final token = await getLoginToken().timeout(const Duration(seconds: 15));
      checkTarget();
      final action = participateSeq == null
          ? 'leave'
          : 'members/$participateSeq/remove';
      final response = await ref
          .read(familyRoomHttpClientProvider)
          .post(
            Uri.parse(
              '$baseUrl/family-room/${Uri.encodeComponent(familyRoomId)}/$action',
            ),
            headers: {'Authorization': 'Bearer $token'},
          )
          .timeout(const Duration(seconds: 30));
      checkTarget();
      if (response.statusCode != 200) {
        throw FamilyRoomMembershipFailure(
          getErrorMessage(response, '참여 종료를 처리하지 못했습니다.'),
        );
      }
      final body = jsonDecode(utf8.decode(response.bodyBytes));
      if (body is! Map ||
          body['result'] != 'OK' ||
          body['family_room_id'] != familyRoomId ||
          (participateSeq == null
              ? body['user_id'] != memberId
              : body['participate_seq'] != participateSeq)) {
        throw const FamilyRoomMembershipFailure(
          '처리 결과를 확인하지 못했습니다. 목록을 새로고침해 주세요.',
        );
      }
      if (participateSeq == null) {
        // 종료된 공간은 즉시 선택 상태에서 제거해 하위 기능이 이전 권한을 재사용하지 않게 한다.
        state = FamilyRoomState(
          rooms: state.rooms
              .where((room) => room.familyRoomId != familyRoomId)
              .toList(),
          participations: Map.of(state.participations)..remove(familyRoomId),
        );
      }
    } on FamilyRoomMembershipFailure {
      rethrow;
    } on TimeoutException {
      throw const FamilyRoomMembershipFailure(
        '결과 확인이 지연됩니다. 공간·가족 목록을 새로고침해 처리 여부를 확인해 주세요.',
      );
    } catch (_) {
      throw const FamilyRoomMembershipFailure(
        '참여 종료 결과를 확인하지 못했습니다. 연결과 목록을 확인해 주세요.',
      );
    } finally {
      if (isCurrentRequest(requestKey, uid)) {
        state = state.copyWith(isLoading: false);
      }
    }
  }

  Future<void> deleteRoom({
    required String familyRoomId,
    required String recipientName,
    required String confirmationName,
  }) async {
    if (state.isLoading) {
      throw const FamilyRoomDeleteFailure('다른 요청을 처리 중이에요. 잠시 후 다시 시도해 주세요.');
    }
    final requestKey = sessionKey;
    final requestUid = ref.read(firebaseAuthProvider).currentUser?.uid;
    void checkTarget() {
      if (!isCurrentRequest(requestKey, requestUid) ||
          requestUid == null ||
          state.selectedRoomId != familyRoomId ||
          state.selectedRoom?.careRecipientName != recipientName ||
          state.selectedParticipation?.isRepresentative != true ||
          state.selectedParticipation?.isActive != true) {
        throw const FamilyRoomDeleteFailure(
          '계정·공간 또는 권한이 변경됐어요. 화면을 다시 열어 주세요.',
        );
      }
      if (confirmationName.trim() != recipientName) {
        throw const FamilyRoomDeleteFailure('돌봄 대상자 이름을 정확히 입력해 주세요.');
      }
    }

    checkTarget();
    state = state.copyWith(isLoading: true, clearError: true);
    try {
      final token = await getLoginToken().timeout(const Duration(seconds: 15));
      checkTarget();
      final response = await ref
          .read(familyRoomHttpClientProvider)
          .delete(
            Uri.parse(
              '$baseUrl/family-room/${Uri.encodeComponent(familyRoomId)}',
            ),
            headers: {'Authorization': 'Bearer $token'},
          )
          .timeout(const Duration(seconds: 30));
      checkTarget();
      if (response.statusCode != 200) {
        throw FamilyRoomDeleteFailure(
          getErrorMessage(response, '돌봄 공간을 삭제하지 못했어요. 다시 시도해 주세요.'),
        );
      }
      final body = jsonDecode(utf8.decode(response.bodyBytes));
      if (body is! Map ||
          body['result'] != 'OK' ||
          body['family_room_id'] != familyRoomId ||
          body['family_room_deleted_at'] == null) {
        throw const FamilyRoomDeleteFailure(
          '삭제 결과를 확인하지 못했어요. 다시 시도하거나 공간 목록을 새로고침해 주세요.',
        );
      }
      state = FamilyRoomState(
        rooms: state.rooms
            .where((room) => room.familyRoomId != familyRoomId)
            .toList(),
        participations: Map.of(state.participations)..remove(familyRoomId),
      );
    } on FamilyRoomDeleteFailure {
      rethrow;
    } on TimeoutException {
      throw const FamilyRoomDeleteFailure(
        '삭제 결과 확인이 지연되고 있어요. 다시 시도하거나 공간 목록을 새로고침해 주세요.',
      );
    } catch (_) {
      throw const FamilyRoomDeleteFailure(
        '삭제 결과를 확인하지 못했어요. 연결 상태를 확인하고 다시 시도해 주세요.',
      );
    } finally {
      if (isCurrentRequest(requestKey, requestUid)) {
        state = state.copyWith(isLoading: false);
      }
    }
  }

  // 대상자를 등록하고 돌봄 공간을 생성한다.
  Future<bool> createRoom({
    required String name,
    required int gender,
    String? birthDate,
    String? address,
    String? notes,
  }) async {
    if (state.isLoading) {
      return false;
    }

    final requestKey = sessionKey;
    final requestUid = ref.read(firebaseAuthProvider).currentUser?.uid;

    state = state.copyWith(isLoading: true, clearError: true);

    try {
      final token = await getLoginToken();

      if (!isCurrentRequest(requestKey, requestUid)) {
        return false;
      }

      final response = await http
          .post(
            Uri.parse('$baseUrl/family-room'),
            headers: {
              'Content-Type': 'application/json; charset=utf-8',
              'Authorization': 'Bearer $token',
            },
            body: jsonEncode({
              'care_recipient_name': name,
              'gender': gender,
              'birth_date': birthDate,
              'care_address': address,
              'special_notes': notes,
            }),
          )
          .timeout(const Duration(seconds: 10));

      if (!isCurrentRequest(requestKey, requestUid)) {
        return false;
      }

      if (response.statusCode != 201) {
        throw Exception(getErrorMessage(response, '돌봄 공간을 생성하지 못했습니다.'));
      }

      // 목록 재조회는 입력 화면에서 돌아온 뒤 실행한다.
      state = state.copyWith(isLoading: false, clearError: true);

      return true;
    } catch (error) {
      if (!isCurrentRequest(requestKey, requestUid)) {
        return false;
      }

      state = state.copyWith(isLoading: false, errorMessage: error.toString());

      return false;
    }
  } // build

  // 현재 주보호자가 대상자 정보를 수정한다.
  Future<void> updateRecipient({
    required String familyRoomId,
    required String name,
    required int gender,
    String? birthDate,
    String? address,
    String? notes,
  }) async {
    final requestKey = sessionKey;
    final requestUid = ref.read(firebaseAuthProvider).currentUser?.uid;

    final token = await getLoginToken();

    if (!isCurrentRequest(requestKey, requestUid)) {
      throw Exception('로그인 상태가 변경되었습니다.');
    }

    final response = await http
        .put(
          Uri.parse(
            '$baseUrl/family-room/'
            '${Uri.encodeComponent(familyRoomId)}/recipient',
          ),
          headers: {
            'Content-Type': 'application/json; charset=utf-8',
            'Authorization': 'Bearer $token',
          },
          body: jsonEncode({
            'care_recipient_name': name.trim(),
            'gender': gender,
            'birth_date': birthDate,
            'care_address': address,
            'special_notes': notes,
          }),
        )
        .timeout(const Duration(seconds: 15));

    if (!isCurrentRequest(requestKey, requestUid)) {
      throw Exception('로그인 상태가 변경되었습니다.');
    }

    if (response.statusCode != 200) {
      throw Exception(getErrorMessage(response, '대상자 정보를 수정하지 못했습니다.'));
    }
  }
} // class
