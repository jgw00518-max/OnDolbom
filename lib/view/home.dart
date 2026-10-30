import 'package:ondolbom/l10n/app_strings.dart';
import 'package:ondolbom/view/auth/account_reactivation_view.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:ondolbom/vm/auth/auth_vm.dart';
import 'package:ondolbom/vm/auth/user_profile_vm.dart';
import 'package:ondolbom/view/auth/profile_form_view.dart';
import 'package:ondolbom/view/auth/widgets/login_loading_view.dart';
import 'package:ondolbom/view/family_room/family_room_list.dart';

class Home extends ConsumerWidget {
  const Home({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final operation = ref.watch(authVmProvider);
    // Firebase 로그인과 MySQL 사용자 등록은 별개이므로 서버 프로필을 추가 조회한다.
    final profile = ref.watch(userProfileProvider);
    final registration = ref.watch(profileRegistrationProvider);
    final inactive = profile.error;
    if (inactive is AccountInactiveException) {
      return AccountReactivationView(account: inactive);
    }

    if (profile.isLoading) {
      return const LoginLoadingView();
    }
    // MySQL 사용자 정보 등록까지 완료하면 공간 목록을 보여준다.
    if (profile.asData?.value != null) {
      return const FamilyRoomList();
    }
    return Scaffold(
      appBar: AppBar(title: Text(AppStrings.tr(context, '온돌봄'))),
      body: SingleChildScrollView(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                profile.when(
                  loading: () => const Padding(
                    padding: EdgeInsets.all(12),
                    child: CircularProgressIndicator(),
                  ),
                  error: (error, _) => Column(
                    children: [
                      Text(
                        AppStrings.error(context, error.toString()),
                        textAlign: TextAlign.center,
                      ),
                      TextButton(
                        onPressed: () => ref.invalidate(userProfileProvider),
                        child: Text(AppStrings.tr(context, '사용자 정보 다시 확인')),
                      ),
                    ],
                  ),
                  // 서버가 미등록으로 응답한 경우에만 필수 정보 입력 폼을 표시한다.
                  data: (value) => value == null
                      ? const ProfileFormView()
                      : const SizedBox.shrink(),
                ),
                if (operation.hasError)
                  Text(
                    AppStrings.error(
                      context,
                      authErrorMessage(operation.error!),
                    ),
                  ),
                const SizedBox(height: 24),
                FilledButton(
                  // 프로필 저장 도중 계정을 바꾸지 않도록 로그아웃도 잠시 막는다.
                  onPressed: operation.isLoading || registration.isLoading
                      ? null
                      : () {
                          ref.read(authVmProvider.notifier).signOut();
                        },
                  child: Text(
                    operation.isLoading
                        ? AppStrings.tr(context, '처리 중…')
                        : AppStrings.tr(context, '로그아웃'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
