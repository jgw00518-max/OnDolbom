import 'dart:convert';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:ondolbom/model/auth/login_preferences.dart';
import 'package:ondolbom/vm/auth/auth_vm.dart';
import 'package:ondolbom/vm/auth/user_profile_vm.dart';

final accountWithdrawalProvider =
    NotifierProvider.autoDispose<AccountWithdrawalVm, AsyncValue<void>>(
      AccountWithdrawalVm.new,
    );

class AccountWithdrawalVm extends Notifier<AsyncValue<void>> {
  @override
  AsyncValue<void> build() => const AsyncData(null);

  Future<bool> withdraw() async {
    if (state.isLoading) return false;
    state = const AsyncLoading();
    final auth = ref.read(firebaseAuthProvider);
    final client = ref.read(authHttpClientProvider);
    final preferences = ref.read(loginPreferencesProvider);
    final cleanup = ref.read(beforeSignOutProvider);
    final base = ref.read(apiBaseUrlProvider).replaceAll(RegExp(r'/+$'), '');
    try {
      final user = auth.currentUser;
      if (user == null) throw Exception('다시 로그인해 주세요.');
      final token = await user.getIdToken().timeout(
        const Duration(seconds: 10),
      );
      if (token == null || auth.currentUser?.uid != user.uid) {
        throw Exception('로그인 계정이 변경되었습니다.');
      }
      final response = await client
          .delete(
            Uri.parse('$base/auth/account'),
            headers: {'Authorization': 'Bearer $token'},
          )
          .timeout(const Duration(seconds: 60));
      if (response.statusCode != 200) {
        final body = jsonDecode(utf8.decode(response.bodyBytes));
        throw Exception(
          body is Map && body['detail'] is String
              ? body['detail']
              : '회원 탈퇴를 처리하지 못했습니다. 다시 시도해 주세요.',
        );
      }
      // API 확정 이후에만 현재 세션을 종료한다. 실패한 탈퇴는 로그인 상태를 유지한다.
      if (auth.currentUser?.uid != user.uid) {
        throw Exception('로그인 계정이 변경되었습니다.');
      }
      try {
        await cleanup();
      } catch (_) {
        /* 탈퇴 계정의 푸시는 서버에서도 차단한다. */
      }
      try {
        await preferences.clearEmail();
        await preferences.saveAutoLogin(false);
      } catch (_) {
        // 서버 탈퇴 성공을 로컬 설정 저장 실패로 되돌리지 않는다.
      } finally {
        await auth.signOut();
      }
      if (ref.mounted) state = const AsyncData(null);
      return true;
    } catch (error, stack) {
      if (ref.mounted) {
        state = AsyncError(
          error.toString().replaceFirst('Exception: ', ''),
          stack,
        );
      }
      return false;
    }
  }
}
