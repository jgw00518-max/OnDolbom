import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ondolbom/view/auth/profile_form_view.dart';
import 'package:ondolbom/vm/auth/user_profile_vm.dart';

class RecordingRegistration extends ProfileRegistrationVm {
  final calls = <List<String>>[];
  @override
  Future<void> register(String name, String phone) async {
    calls.add([name, phone]);
  }
}

void main() {
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
