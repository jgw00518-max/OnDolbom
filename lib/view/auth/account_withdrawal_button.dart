import 'package:ondolbom/l10n/app_strings.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:ondolbom/theme/app_colors.dart';
import 'package:ondolbom/vm/auth/account_withdrawal_vm.dart';

class AccountWithdrawalButton extends ConsumerWidget {
  const AccountWithdrawalButton({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final operation = ref.watch(accountWithdrawalProvider);
    return PopScope(
      canPop: !operation.isLoading,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Divider(color: AppColors.of(context).border),
          const SizedBox(height: 12),
          Text(
            AppStrings.tr(context, '계정 관리'),
            style: TextStyle(
              color: AppColors.of(context).textSecondary,
              fontSize: 12,
            ),
          ),
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton.icon(
              icon: const Icon(Icons.person_remove_outlined, size: 19),
              style: TextButton.styleFrom(
                foregroundColor: AppColors.resolve(
                  context,
                  const Color(0xFFAD655B),
                ),
                backgroundColor: AppColors.resolve(
                  context,
                  const Color(0xFFF7E5DF),
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
                padding: const EdgeInsets.symmetric(
                  horizontal: 18,
                  vertical: 14,
                ),
              ),
              onPressed: operation.isLoading
                  ? null
                  : () async {
                      // 되돌릴 수 없는 계정 삭제 전에 공간 역할과 기록 보존 범위를 안내한다.
                      final confirmed = await showDialog<bool>(
                        context: context,
                        builder: (dialogContext) => AlertDialog(
                          title: Text(AppStrings.tr(context, '회원 탈퇴하시겠어요?')),
                          content: Text(
                            AppStrings.tr(
                              context,
                              '탈퇴하면 서비스 이용이 즉시 중지되고 회원 데이터는 30일 동안 보관됩니다. 30일이 지나기 전 로그인하면 계정을 다시 활성화할 수 있습니다. 30일 후에는 계정과 개인정보가 삭제되어 복구할 수 없습니다. 가족과 공유한 기록은 작성자를 익명화하여 유지합니다. 주보호자는 역할 이전 또는 공간 삭제가 먼저 필요합니다.',
                            ),
                          ),
                          actions: [
                            TextButton(
                              onPressed: () =>
                                  Navigator.pop(dialogContext, false),
                              child: Text(AppStrings.tr(context, '취소')),
                            ),
                            FilledButton(
                              style: FilledButton.styleFrom(
                                backgroundColor: AppColors.resolve(
                                  context,
                                  const Color(0xFFAD655B),
                                  onAccent: true,
                                ),
                                foregroundColor: AppColors.resolve(
                                  context,
                                  Colors.white,
                                  onAccent: true,
                                ),
                              ),
                              onPressed: () =>
                                  Navigator.pop(dialogContext, true),
                              child: Text(AppStrings.tr(context, '회원 탈퇴')),
                            ),
                          ],
                        ),
                      );
                      if (confirmed != true || !context.mounted) return;
                      final success = await ref
                          .read(accountWithdrawalProvider.notifier)
                          .withdraw();
                      if (success && context.mounted) {
                        Navigator.of(
                          context,
                        ).popUntil((route) => route.isFirst);
                      }
                    },
              label: Text(
                operation.isLoading
                    ? AppStrings.tr(context, '탈퇴 처리 중…')
                    : AppStrings.tr(context, '회원 탈퇴'),
              ),
            ),
          ),
          if (operation.hasError)
            Text(
              AppStrings.error(context, operation.error.toString()),
              style: TextStyle(
                color: AppColors.resolve(context, Color(0xFFAD655B)),
                fontSize: 13,
              ),
            ),
        ],
      ),
    );
  }
}
