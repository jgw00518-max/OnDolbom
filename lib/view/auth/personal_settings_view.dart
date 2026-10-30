import 'package:ondolbom/view/auth/account_withdrawal_button.dart';
import 'package:ondolbom/model/settings/text_size_preferences.dart';
import 'package:ondolbom/vm/settings/text_size_vm.dart';
import 'package:ondolbom/theme/app_colors.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:ondolbom/vm/auth/auth_vm.dart';
import 'package:ondolbom/vm/auth/user_profile_vm.dart';
import 'package:ondolbom/view/auth/profile_edit_view.dart';
import 'package:ondolbom/view/widgets/push_bridge.dart';

class PersonalSettingsView extends ConsumerWidget {
  const PersonalSettingsView({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profileState = ref.watch(userProfileProvider);
    final profile = profileState.asData?.value;
    final user = ref.watch(authUserProvider).asData?.value;
    final textSettings = ref.watch(textSizeProvider);
    final textSize = textSettings.asData?.value;
    final name = profile?.name?.trim().isNotEmpty == true
        ? profile!.name!
        : '가족 사용자';
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.background,
        surfaceTintColor: Colors.transparent,
        foregroundColor: AppColors.textPrimary,
        toolbarHeight: 88,
        centerTitle: true,
        leadingWidth: 62,
        leading: Padding(
          padding: const EdgeInsets.only(left: 14),
          child: Center(
            child: SizedBox.square(
              dimension: 42,
              child: OutlinedButton(
                onPressed: () => Navigator.maybePop(context),
                style: OutlinedButton.styleFrom(
                  padding: EdgeInsets.zero,
                  backgroundColor: AppColors.surface,
                  foregroundColor: AppColors.textPrimary,
                  side: const BorderSide(color: AppColors.border),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(13),
                  ),
                ),
                child: const Icon(Icons.chevron_left),
              ),
            ),
          ),
        ),
        title: const Column(
          children: [
            Text(
              'MY PREFERENCES',
              style: TextStyle(
                color: Color(0xFFA77762),
                fontSize: 8,
                fontWeight: FontWeight.w800,
                letterSpacing: 1.3,
              ),
            ),
            SizedBox(height: 3),
            Text(
              '개인 설정',
              style: TextStyle(
                color: AppColors.textPrimary,
                fontSize: 24,
                fontWeight: FontWeight.w800,
              ),
            ),
          ],
        ),
        actions: [
          Container(
            width: 42,
            height: 42,
            margin: const EdgeInsets.only(right: 20),
            decoration: BoxDecoration(
              color: AppColors.sageLight,
              borderRadius: BorderRadius.circular(14),
            ),
            child: const Icon(
              Icons.settings_outlined,
              color: AppColors.sageDark,
              size: 23,
            ),
          ),
        ],
      ),
      body: Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 560),
          child: ListView(
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 40),
            children: [
              _section('PROFILE'),
              Container(
                padding: const EdgeInsets.all(18),
                decoration: BoxDecoration(
                  color: AppColors.peachLight,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Row(
                  children: [
                    Container(
                      width: 58,
                      height: 58,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: AppColors.primary,
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: AppColors.surface.withValues(alpha: 0.65),
                          width: 3,
                        ),
                      ),
                      child: Text(
                        name.characters.first,
                        style: const TextStyle(
                          color: Color(0xFF684331),
                          fontSize: 22,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                    const SizedBox(width: 13),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            name,
                            style: const TextStyle(
                              color: AppColors.textPrimary,
                              fontSize: 19,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          const SizedBox(height: 5),
                          Text(
                            profile?.email ?? user?.email ?? '등록 정보 없음',
                            style: const TextStyle(
                              color: Color(0xFF866E63),
                              fontSize: 11,
                              height: 1.5,
                            ),
                          ),
                          const SizedBox(height: 3),
                          Text(
                            profile?.phone ?? '전화번호 등록 정보 없음',
                            style: const TextStyle(
                              color: Color(0xFF866E63),
                              fontSize: 11,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 6),
                    Tooltip(
                      message: '프로필 수정',
                      child: TextButton.icon(
                        onPressed: profile == null || profileState.isLoading
                            ? null
                            : () => Navigator.of(context).push(
                                MaterialPageRoute<void>(
                                  builder: (_) => const ProfileEditView(),
                                ),
                              ),
                        style: TextButton.styleFrom(
                          backgroundColor: AppColors.surface.withValues(
                            alpha: 0.55,
                          ),
                          foregroundColor: const Color(0xFF794F3C),
                          minimumSize: const Size(0, 36),
                          padding: const EdgeInsets.symmetric(horizontal: 9),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                        ),
                        icon: const Icon(Icons.edit_outlined, size: 14),
                        label: const Text(
                          '수정',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              if (profileState.isLoading)
                const Padding(
                  padding: EdgeInsets.only(top: 10),
                  child: LinearProgressIndicator(),
                ),
              if (profileState.hasError)
                Column(
                  children: [
                    Text(profileState.error.toString()),
                    TextButton(
                      onPressed: () => ref.invalidate(userProfileProvider),
                      child: const Text('프로필 다시 조회'),
                    ),
                  ],
                ),
              const SizedBox(height: 28),
              _section('APPEARANCE'),
              _card(
                Column(
                  children: [
                    _settingRow(
                      icon: _icon(
                        Icons.dark_mode_outlined,
                        const Color(0xFFE8E4EF),
                        const Color(0xFF6E6182),
                      ),
                      title: '다크 모드',
                      subtitle: '어두운 환경에서 편안하게 이용해요',
                      trailing: Semantics(
                        label: '다크 모드 준비 중',
                        child: const Switch(value: false, onChanged: null),
                      ),
                    ),
                    const Divider(height: 1, color: AppColors.border),
                    _settingRow(
                      icon: _icon(
                        Icons.language,
                        AppColors.sageLight,
                        AppColors.sageDark,
                      ),
                      title: '언어 설정',
                      subtitle: '앱에서 사용할 언어를 선택해요',
                      trailing: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 9),
                        decoration: BoxDecoration(
                          color: AppColors.background,
                          border: Border.all(color: AppColors.border),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: DropdownButtonHideUnderline(
                          child: DropdownButton<String>(
                            value: '한국어',
                            onChanged: null,
                            style: const TextStyle(
                              color: AppColors.textPrimary,
                              fontSize: 12,
                            ),
                            items: const [
                              DropdownMenuItem(
                                value: '한국어',
                                child: Text('한국어'),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 28),
              _section('TEXT SIZE'),
              _card(
                Column(
                  children: [
                    _settingRow(
                      icon: _icon(
                        Icons.text_fields,
                        AppColors.peachSoft,
                        const Color(0xFF94644D),
                      ),
                      title: '글씨 크기',
                      subtitle: '읽기 편한 크기로 조절해 보세요',
                    ),
                    Container(
                      padding: const EdgeInsets.all(15),
                      margin: const EdgeInsets.only(bottom: 14),
                      decoration: BoxDecoration(
                        color: const Color(0xFFFFF8F3),
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: Row(
                        children: [
                          Container(
                            width: 36,
                            height: 36,
                            alignment: Alignment.center,
                            decoration: BoxDecoration(
                              color: AppColors.peachLight,
                              borderRadius: BorderRadius.circular(11),
                            ),
                            child: const Text(
                              '가',
                              style: TextStyle(
                                color: AppColors.textPrimary,
                                fontSize: 20,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          const Expanded(
                            child: Text(
                              '가족과 함께하는 따뜻한 하루',
                              style: TextStyle(
                                color: AppColors.textPrimary,
                                fontSize: 13,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    // 전역 설정을 참조해 미리보기와 앱 전체에 같은 크기를 적용한다.
                    Row(
                      children: [
                        for (final size in AppTextSize.values) ...[
                          if (size != AppTextSize.small)
                            const SizedBox(width: 8),
                          Expanded(
                            child: OutlinedButton(
                              onPressed: textSize == null || textSize.saving
                                  ? null
                                  : () => ref
                                        .read(textSizeProvider.notifier)
                                        .select(size),
                              style: OutlinedButton.styleFrom(
                                foregroundColor: textSize?.size == size
                                    ? const Color(0xFF94644D)
                                    : AppColors.textSecondary,
                                backgroundColor: textSize?.size == size
                                    ? AppColors.peachSoft
                                    : AppColors.surface,
                                side: BorderSide(
                                  color: textSize?.size == size
                                      ? AppColors.primary
                                      : AppColors.border,
                                ),
                                minimumSize: const Size.fromHeight(40),
                                padding: EdgeInsets.zero,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                              ),
                              child: Text(
                                size.label,
                                style: const TextStyle(fontSize: 12),
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                    if (textSettings.isLoading || (textSize?.saving ?? false))
                      const Padding(
                        padding: EdgeInsets.only(top: 10),
                        child: LinearProgressIndicator(),
                      ),
                    if (textSize?.error != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 10),
                        child: Text(
                          textSize!.error!,
                          style: TextStyle(
                            color: Theme.of(context).colorScheme.error,
                          ),
                        ),
                      ),
                    if (textSettings.hasError)
                      Column(
                        children: [
                          const Text('글씨 크기 설정을 불러오지 못했습니다.'),
                          TextButton(
                            onPressed: () => ref.invalidate(textSizeProvider),
                            child: const Text('글씨 크기 다시 불러오기'),
                          ),
                        ],
                      ),
                    const SizedBox(height: 14),
                  ],
                ),
              ),
              const Padding(
                padding: EdgeInsets.only(top: 10),
                child: Text(
                  '다크 모드·언어 설정은 준비 중이에요.',
                  style: TextStyle(
                    color: AppColors.textSecondary,
                    fontSize: 11,
                  ),
                ),
              ),
              const SizedBox(height: 28),
              _section('NOTIFICATIONS'),
              const PushSettingsTile(),
              const SizedBox(height: 28),
              const SizedBox(height: 32),
              const AccountWithdrawalButton(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _section(String label) => Padding(
    padding: const EdgeInsets.only(left: 3, bottom: 10),
    child: Text(
      label,
      style: const TextStyle(
        color: Color(0xFFA48F85),
        fontSize: 10,
        fontWeight: FontWeight.w800,
        letterSpacing: 1.4,
      ),
    ),
  );

  Widget _card(Widget child) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
    decoration: BoxDecoration(
      color: AppColors.surface,
      border: Border.all(color: AppColors.border),
      borderRadius: BorderRadius.circular(19),
      boxShadow: [
        BoxShadow(
          color: const Color(0xFF594135).withValues(alpha: 0.04),
          blurRadius: 22,
          offset: const Offset(0, 7),
        ),
      ],
    ),
    child: Material(color: Colors.transparent, child: child),
  );

  Widget _icon(IconData icon, Color background, Color color) => Container(
    width: 40,
    height: 40,
    decoration: BoxDecoration(
      color: background,
      borderRadius: BorderRadius.circular(13),
    ),
    child: Icon(icon, color: color, size: 22),
  );

  Widget _settingRow({
    required Widget icon,
    required String title,
    required String subtitle,
    Widget? trailing,
  }) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 18),
    child: Row(
      children: [
        icon,
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(
                  color: AppColors.textPrimary,
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                subtitle,
                style: const TextStyle(
                  color: AppColors.textSecondary,
                  fontSize: 11,
                  height: 1.5,
                ),
              ),
            ],
          ),
        ),
        if (trailing != null) ...[const SizedBox(width: 8), trailing],
      ],
    ),
  );
}
