import 'package:ondolbom/model/family/family_room.dart';
import 'package:ondolbom/model/family/participate.dart';

class FamilyRoomState {
  final List<FamilyRoom> rooms;
  final Map<String, Participate> participations;
  final String? selectedRoomId;
  final bool isLoading;
  final String? errorMessage;

  const FamilyRoomState({
    this.rooms = const [],
    this.participations = const {},
    this.selectedRoomId,
    this.isLoading = false,
    this.errorMessage,
  });

  // 선택한 공간 정보를 가져온다.
  FamilyRoom? get selectedRoom {
    for (final room in rooms) {
      if (room.familyRoomId == selectedRoomId) {
        return room;
      }
    }

    return null;
  }

  // 선택한 공간에서 현재 사용자의 참여 정보를 가져온다.
  Participate? get selectedParticipation {
    return participations[selectedRoomId];
  }

  FamilyRoomState copyWith({
    List<FamilyRoom>? rooms,
    Map<String, Participate>? participations,
    String? selectedRoomId,
    bool? isLoading,
    String? errorMessage,
    bool clearSelection = false,
    bool clearError = false,
  }) {
    return FamilyRoomState(
      rooms: rooms ?? this.rooms,
      participations: participations ?? this.participations,
      selectedRoomId: clearSelection
          ? null
          : selectedRoomId ?? this.selectedRoomId,
      isLoading: isLoading ?? this.isLoading,
      errorMessage: clearError
          ? null
          : errorMessage ?? this.errorMessage,
    );
  }
}