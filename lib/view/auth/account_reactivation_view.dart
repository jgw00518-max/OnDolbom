import 'package:ondolbom/l10n/app_strings.dart';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:ondolbom/theme/app_colors.dart';
import 'package:ondolbom/vm/auth/auth_vm.dart';
import 'package:ondolbom/vm/auth/user_profile_vm.dart';

class AccountReactivationView extends ConsumerStatefulWidget {
  const AccountReactivationView({super.key, required this.account});
  final AccountInactiveException account;
  @override
  ConsumerState<AccountReactivationView> createState() =>
      _AccountReactivationViewState();
}

class _AccountReactivationViewState
    extends ConsumerState<AccountReactivationView> {
  bool busy = false;
  String? error;
  Future<void> reactivate() async {
    if (busy) return;
    setState(() {
      busy = true;
      error = null;
    });
    try {
      final auth = ref.read(firebaseAuthProvider);
      final user = auth.currentUser;
      if (user == null) throw Exception('다시 로그인해 주세요.');
      final token = await user.getIdToken();
      final base = ref.read(apiBaseUrlProvider).replaceAll(RegExp(r'/+$'), '');
      final response = await ref
          .read(authHttpClientProvider)
          .post(
            Uri.parse('$base/auth/account/reactivate'),
            headers: {'Authorization': 'Bearer $token'},
          )
          .timeout(const Duration(seconds: 20));
      if (response.statusCode != 200) {
        final body = jsonDecode(utf8.decode(response.bodyBytes));
        throw Exception(
          body is Map && body['detail'] is String
              ? body['detail']
              : '계정을 활성화하지 못했습니다. 다시 시도해 주세요.',
        );
      }
      // 요청 중 계정이 전환되었다면 다른 계정의 화면을 갱신하지 않는다.
      if (mounted && auth.currentUser?.uid == user.uid) {
        ref.invalidate(userProfileProvider);
      }
    } catch (e) {
      if (mounted) {
        setState(() => error = e.toString().replaceFirst('Exception: ', ''));
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: AppColors.of(context).background,
    appBar: AppBar(
      centerTitle: true,
      automaticallyImplyLeading: false,
      title: Text(AppStrings.tr(context, '비활성 계정')),
    ),
    body: Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 480),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Icon(
                Icons.person_outline,
                size: 56,
                color: AppColors.of(context).sageDark,
              ),
              const SizedBox(height: 24),
              Text(
                widget.account.canReactivate
                    ? AppStrings.tr(context, '다시 함께하시겠어요?')
                    : AppStrings.tr(context, '재활성화 기간이 지났어요'),
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 16),
              Text(
                widget.account.canReactivate
                    ? AppStrings.format(
                        context,
                        "탈퇴 후 30일 동안 서비스 이용이 중지된 상태입니다. 활성화 버튼을 누르면 계정을 다시 이용할 수 있어요.\n\n재활성화 기한: {0}",
                        [widget.account.reactivationUntil],
                      )
                    : AppStrings.tr(context, '탈퇴 후 30일이 지나 계정을 복구할 수 없습니다.'),
                style: TextStyle(
                  height: 1.6,
                  color: AppColors.of(context).textSecondary,
                ),
              ),
              const SizedBox(height: 24),
              if (error != null)
                Text(
                  AppStrings.error(context, error!),
                  style: const TextStyle(color: Colors.red),
                ),
              if (widget.account.canReactivate)
                FilledButton(
                  style: FilledButton.styleFrom(
                    backgroundColor: AppColors.resolve(
                      context,
                      AppColors.primary,
                      onAccent: true,
                    ),
                    foregroundColor: AppColors.resolve(
                      context,
                      AppColors.textPrimary,
                      onAccent: true,
                    ),
                    padding: const EdgeInsets.all(18),
                  ),
                  onPressed: busy ? null : reactivate,
                  child: Text(
                    busy
                        ? AppStrings.tr(context, '활성화 중…')
                        : AppStrings.tr(context, '계정 활성화'),
                  ),
                ),
              TextButton(
                onPressed: busy
                    ? null
                    : () => ref.read(authVmProvider.notifier).signOut(),
                child: Text(AppStrings.tr(context, '로그인 화면으로')),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}
