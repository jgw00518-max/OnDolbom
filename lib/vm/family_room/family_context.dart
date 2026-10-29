import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:ondolbom/vm/auth/auth_vm.dart';
import 'package:ondolbom/vm/auth/user_profile_vm.dart' as profile;
import 'package:ondolbom/vm/family_room/family_room_notifier.dart';

export 'package:ondolbom/vm/auth/user_profile_vm.dart' show apiBaseUrlProvider;

typedef FamilyContext = ({String familyRoomId, String userId, String roomName});

// 실행 옵션 대신 실제 로그인 프로필과 선택된 돌봄 공간을 사용한다.
final familyContextProvider = Provider<FamilyContext>((ref) {
  final room = ref.watch(familyRoomProvider).selectedRoom;
  final user = ref.watch(profile.userProfileProvider).asData?.value;
  return (
    familyRoomId: room?.familyRoomId ?? '',
    userId: user?.userId ?? '',
    roomName: room == null ? '가족 돌봄 공간' : '${room.careRecipientName} 님의 돌봄 공간',
  );
});

// 계정 전환 전의 화면에서 새 계정의 토큰을 사용하지 않도록 UID를 고정한다.
final apiTokenLoaderProvider = Provider<Future<String?> Function()>((ref) {
  final uid = ref.watch(authUserProvider).asData?.value?.uid;
  final auth = ref.watch(firebaseAuthProvider);
  return () async {
    final user = auth.currentUser;
    if (uid == null || user == null || user.uid != uid) return null;
    try {
      final token = await user.getIdToken();
      if (auth.currentUser?.uid != uid) return null;
      return token;
    } on FirebaseAuthException {
      return null;
    }
  };
});
