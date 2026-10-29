import 'package:firebase_auth/firebase_auth.dart';
import 'package:ondolbom/vm/auth/auth_vm.dart';
import '../vm/user_profile_vm_test.dart' show TestAuth;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ondolbom/view/auth/profile_form_view.dart';
import 'package:ondolbom/vm/auth/user_profile_vm.dart';

// DB 저장 대신 제출값만 기록해 필수 입력과 두 전화번호 형식의 허용 여부를 확인한다.
class RecordingRegistration extends ProfileRegistrationVm {
  final calls = <List<String>>[];
  @override
  Future<void> register(String name, String phone) async {
    calls.add([name, phone]);
  }
}

class VerificationUser extends Fake implements User {
  int sent = 0;
  @override
  Future<void> sendEmailVerification([
    ActionCodeSettings? actionCodeSettings,
  ]) async {
    sent++;
  }
}

class VerificationRequired extends ProfileRegistrationVm {
  @override
  AsyncValue<void> build() => AsyncError(
    const ProfileLoadException('회원가입 이메일 인증을 먼저 완료해 주세요.'),
    StackTrace.current,
  );
}

void main() {
  testWidgets('미인증 계정은 인증 메일을 요청해도 입력한 프로필을 유지한다', (tester) async {
    final user = VerificationUser();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          firebaseAuthProvider.overrideWithValue(TestAuth(user)),
          profileRegistrationProvider.overrideWith(VerificationRequired.new),
        ],
        child: const MaterialApp(
          home: Scaffold(body: SingleChildScrollView(child: ProfileFormView())),
        ),
      ),
    );
    await tester.enterText(find.byType(TextFormField).at(0), '가족');
    await tester.enterText(find.byType(TextFormField).at(1), '01012345678');
    await tester.ensureVisible(find.text('이메일 인증 메일 보내기'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('이메일 인증 메일 보내기'));
    await tester.pumpAndSettle();
    expect(user.sent, 1);
    expect(find.textContaining('인증 메일을 보냈습니다.'), findsOneWidget);
    expect(find.text('가족'), findsOneWidget);
    expect(find.text('01012345678'), findsOneWidget);
  });

  testWidgets('Name and phone required; both phone formats accepted', (
    tester,
  ) async {
    final vm = RecordingRegistration();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [profileRegistrationProvider.overrideWith(() => vm)],
        child: const MaterialApp(home: Scaffold(body: ProfileFormView())),
      ),
    );
    await tester.tap(find.text('가족 사용자 정보 저장'));
    await tester.pump();
    expect(find.text('이름을 입력해 주세요.'), findsOneWidget);
    expect(vm.calls, isEmpty);
    await tester.enterText(find.byType(TextFormField).at(0), '가족');
    for (final phone in ['01012345678', '010-1234-5678']) {
      await tester.enterText(find.byType(TextFormField).at(1), phone);
      await tester.tap(find.text('가족 사용자 정보 저장'));
      await tester.pump();
    }
    expect(vm.calls, [
      ['가족', '01012345678'],
      ['가족', '010-1234-5678'],
    ]);
  });
}
