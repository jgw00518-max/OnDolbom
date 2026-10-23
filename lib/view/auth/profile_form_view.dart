import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:ondolbom/vm/auth/user_profile_vm.dart';

/// 홈의 미등록 상태에 표시하는 가족 프로필 입력 폼.
class ProfileFormView extends ConsumerStatefulWidget {
  const ProfileFormView({super.key});
  @override
  ConsumerState<ProfileFormView> createState() => _ProfileFormViewState();
}

class _ProfileFormViewState extends ConsumerState<ProfileFormView> {
  final _form = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _phone = TextEditingController();

  @override
  void dispose() {
    _name.dispose();
    _phone.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(profileRegistrationProvider);
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 440),
      child: Form(
        key: _form,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text('가족 사용자 정보 등록', style: TextStyle(fontSize: 20)),
            const SizedBox(height: 16),
            TextFormField(
              controller: _name,
              enabled: !state.isLoading,
              decoration: const InputDecoration(labelText: '이름 (필수)'),
              autofillHints: const [AutofillHints.name],
              validator: (value) => value == null || value.trim().isEmpty
                  ? '이름을 입력해 주세요.'
                  : value.trim().runes.length > 20
                  ? '이름은 20자 이내로 입력해 주세요.'
                  : null,
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _phone,
              enabled: !state.isLoading,
              decoration: const InputDecoration(
                labelText: '전화번호 (필수)',
                hintText: '01012345678 또는 010-1234-5678',
              ),
              keyboardType: TextInputType.phone,
              autofillHints: const [AutofillHints.telephoneNumber],
              validator: (value) =>
                  !RegExp(
                    r'^010(?:[0-9]{8}|-[0-9]{4}-[0-9]{4})$',
                  ).hasMatch(value?.trim() ?? '')
                  ? '01012345678 또는 010-1234-5678로 입력해 주세요.'
                  : null,
            ),
            if (state.hasError)
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: Text(
                  state.error.toString(),
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: state.isLoading
                  ? null
                  : () {
                      if (_form.currentState!.validate()) {
                        ref
                            .read(profileRegistrationProvider.notifier)
                            .register(_name.text, _phone.text);
                      }
                    },
              child: Text(state.isLoading ? '저장 중…' : '가족 사용자 정보 저장'),
            ),
          ],
        ),
      ),
    );
  }
}
