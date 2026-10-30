import 'package:ondolbom/l10n/app_strings.dart';
import 'package:ondolbom/vm/auth/auth_vm.dart';
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
  bool _sendingVerification = false;
  String? _verificationNotice;
  final _name = TextEditingController();
  final _phone = TextEditingController();

  @override
  void dispose() {
    _name.dispose();
    _phone.dispose();
    super.dispose();
  }

  Future<void> _sendVerification() async {
    if (_sendingVerification) return;
    setState(() {
      _sendingVerification = true;
      _verificationNotice = null;
    });
    try {
      final user = ref.read(firebaseAuthProvider).currentUser;
      if (user == null) throw StateError('signed out');
      // 기존 미인증 계정도 소유한 이메일을 인증한 뒤 로컬 프로필을 등록할 수 있다.
      await user.sendEmailVerification();
      if (mounted) {
        setState(
          () => _verificationNotice =
              '인증 메일을 보냈습니다. 메일의 링크로 인증한 뒤 아래 저장 버튼을 다시 눌러 주세요.',
        );
      }
    } catch (_) {
      if (mounted) {
        setState(
          () => _verificationNotice = '인증 메일을 보내지 못했습니다. 잠시 후 다시 시도해 주세요.',
        );
      }
    } finally {
      if (mounted) setState(() => _sendingVerification = false);
    }
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
            Text(
              AppStrings.tr(context, '가족 사용자 정보 등록'),
              style: TextStyle(fontSize: 20),
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _name,
              enabled: !state.isLoading,
              decoration: InputDecoration(
                labelText: AppStrings.tr(context, '이름 (필수)'),
              ),
              autofillHints: const [AutofillHints.name],
              // 필수 여부와 실제 DB name 컬럼의 20자 제한을 먼저 안내한다.
              validator: (value) => value == null || value.trim().isEmpty
                  ? AppStrings.tr(context, '이름을 입력해 주세요.')
                  : value.trim().runes.length > 20
                  ? AppStrings.tr(context, '이름은 20자 이내로 입력해 주세요.')
                  : null,
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _phone,
              enabled: !state.isLoading,
              decoration: InputDecoration(
                labelText: AppStrings.tr(context, '전화번호 (필수)'),
                hintText: AppStrings.tr(
                  context,
                  '01012345678 또는 010-1234-5678',
                ),
              ),
              keyboardType: TextInputType.phone,
              autofillHints: const [AutofillHints.telephoneNumber],
              // 두 입력 형식만 허용한다. 저장 형식 통일은 서버에서 다시 수행한다.
              validator: (value) =>
                  !RegExp(
                    r'^010(?:[0-9]{8}|-[0-9]{4}-[0-9]{4})$',
                  ).hasMatch(value?.trim() ?? '')
                  ? AppStrings.tr(
                      context,
                      '01012345678 또는 010-1234-5678로 입력해 주세요.',
                    )
                  : null,
            ),
            if (state.hasError)
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: Text(
                  AppStrings.error(context, state.error.toString()),
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ),
            // 이메일 미인증 오류에만 복구 경로를 제공하고 탈퇴 계정은 우회하지 않는다.
            if (state.hasError &&
                state.error.toString().contains('회원가입 이메일 인증'))
              OutlinedButton.icon(
                onPressed: state.isLoading || _sendingVerification
                    ? null
                    : _sendVerification,
                icon: const Icon(Icons.mark_email_read_outlined),
                label: Text(
                  _sendingVerification
                      ? AppStrings.tr(context, '인증 메일 보내는 중…')
                      : AppStrings.tr(context, '이메일 인증 메일 보내기'),
                ),
              ),
            if (_verificationNotice != null)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(_verificationNotice!),
              ),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: state.isLoading || _sendingVerification
                  ? null
                  : () {
                      // 실패 시 입력을 유지하고, 성공 시 VM이 프로필 재조회를 요청한다.
                      if (_form.currentState!.validate()) {
                        ref
                            .read(profileRegistrationProvider.notifier)
                            .register(_name.text, _phone.text);
                      }
                    },
              child: Text(
                state.isLoading
                    ? AppStrings.tr(context, '저장 중…')
                    : AppStrings.tr(context, '가족 사용자 정보 저장'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
