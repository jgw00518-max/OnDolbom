import 'package:ondolbom/theme/app_colors.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:ondolbom/model/auth/user_profile.dart';
import 'package:ondolbom/vm/auth/auth_vm.dart';
import 'package:ondolbom/vm/auth/profile_edit_vm.dart';
import 'package:ondolbom/vm/auth/user_profile_vm.dart';

class ProfileEditView extends ConsumerWidget {
  const ProfileEditView({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profile = ref.watch(userProfileProvider);
    final session = ref.watch(authUserProvider).asData?.value;
    final operation = ref.watch(profileEditProvider);
    ref.listen(authUserProvider, (previous, next) {
      if (previous?.asData?.value?.uid != null &&
          next.hasValue &&
          previous?.asData?.value?.uid != next.asData?.value?.uid) {
        Navigator.of(context).popUntil((route) => route.isFirst);
      }
    });
    return PopScope(
      canPop: !operation.isLoading,
      child: Scaffold(
        backgroundColor: AppColors.background,
        appBar: AppBar(
          backgroundColor: AppColors.background,
          surfaceTintColor: Colors.transparent,
          title: const Text(
            '프로필 수정',
            style: TextStyle(color: AppColors.textPrimary),
          ),
        ),
        body: profile.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (error, _) => Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(error.toString(), textAlign: TextAlign.center),
                TextButton(
                  onPressed: () => ref.invalidate(userProfileProvider),
                  child: const Text('프로필 다시 조회'),
                ),
              ],
            ),
          ),
          data: (value) => value == null || session == null
              ? const Center(child: Text('로그인과 사용자 등록 상태를 확인해 주세요.'))
              : _ProfileEditForm(
                  key: ValueKey('${session.uid}/${value.userId}'),
                  profile: value,
                  email: value.email ?? session.email ?? '',
                ),
        ),
      ),
    );
  }
}

class _ProfileEditForm extends ConsumerStatefulWidget {
  const _ProfileEditForm({
    super.key,
    required this.profile,
    required this.email,
  });
  final UserProfile profile;
  final String email;
  @override
  ConsumerState<_ProfileEditForm> createState() => _ProfileEditFormState();
}

class _ProfileEditFormState extends ConsumerState<_ProfileEditForm> {
  final _form = GlobalKey<FormState>();
  late final TextEditingController _name;
  late final TextEditingController _phone;
  @override
  void initState() {
    super.initState();
    _name = TextEditingController(text: widget.profile.name ?? '');
    _phone = TextEditingController(text: widget.profile.phone ?? '');
  }

  @override
  void dispose() {
    _name.dispose();
    _phone.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_form.currentState!.validate()) return;
    final success = await ref
        .read(profileEditProvider.notifier)
        .save(_name.text, _phone.text);
    if (!mounted || !success) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('프로필을 수정했습니다.')));
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final operation = ref.watch(profileEditProvider);
    return Align(
      alignment: Alignment.topCenter,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 560),
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Form(
            key: _form,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text(
                  '개인 프로필',
                  style: TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: 24,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 12),
                const Text(
                  '이름과 전화번호를 수정할 수 있어요.',
                  style: TextStyle(color: AppColors.textSecondary),
                ),
                const SizedBox(height: 24),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('이메일'),
                  subtitle: SelectableText(widget.email),
                ),
                const Text(
                  '이메일은 로그인 계정 정보이므로 이 화면에서 변경할 수 없어요.',
                  style: TextStyle(
                    color: AppColors.textSecondary,
                    fontSize: 12,
                  ),
                ),
                const SizedBox(height: 24),
                TextFormField(
                  controller: _name,
                  enabled: !operation.isLoading,
                  decoration: _input('이름 (필수)'),
                  autofillHints: const [AutofillHints.name],
                  validator: (value) => value == null || value.trim().isEmpty
                      ? '이름을 입력해 주세요.'
                      : value.trim().runes.length > 20
                      ? '이름은 20자 이내로 입력해 주세요.'
                      : null,
                ),
                const SizedBox(height: 20),
                TextFormField(
                  controller: _phone,
                  enabled: !operation.isLoading,
                  decoration: _input(
                    '전화번호 (필수)',
                  ).copyWith(hintText: '01012345678 또는 010-1234-5678'),
                  keyboardType: TextInputType.phone,
                  autofillHints: const [AutofillHints.telephoneNumber],
                  validator: (value) =>
                      !RegExp(
                        r'^010(?:[0-9]{8}|-[0-9]{4}-[0-9]{4})$',
                      ).hasMatch(value?.trim() ?? '')
                      ? '01012345678 또는 010-1234-5678로 입력해 주세요.'
                      : null,
                ),
                if (operation.hasError)
                  Padding(
                    padding: const EdgeInsets.only(top: 16),
                    child: Text(
                      operation.error.toString(),
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                  ),
                if (operation.hasError)
                  TextButton(
                    onPressed: () => ref.invalidate(userProfileProvider),
                    child: const Text('프로필 다시 조회'),
                  ),
                const SizedBox(height: 28),
                FilledButton(
                  onPressed: operation.isLoading ? null : _save,
                  style: FilledButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    foregroundColor: AppColors.textPrimary,
                    minimumSize: const Size.fromHeight(54),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                  child: Text(operation.isLoading ? '저장 중…' : '변경사항 저장'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  InputDecoration _input(String label) => InputDecoration(
    labelText: label,
    filled: true,
    fillColor: AppColors.surface,
    border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
    enabledBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(14),
      borderSide: const BorderSide(color: AppColors.border),
    ),
    contentPadding: const EdgeInsets.all(18),
  );
}
