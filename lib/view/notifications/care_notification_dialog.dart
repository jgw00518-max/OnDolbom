import 'package:flutter/material.dart';
import 'package:ondolbom/l10n/app_strings.dart';
import 'package:ondolbom/model/notifications/schedule_notification.dart';
import 'package:ondolbom/theme/app_colors.dart';

/// 단순 공간 안내는 일정 조회·공간 재진입 없이 기존 온돌봄 상세 팝업의 구성으로 표시한다.
class CareNotificationDialog extends StatelessWidget {
  const CareNotificationDialog({super.key, required this.item});
  final ScheduleNotification item;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    final icon = switch (item.type) {
      'memo_created' => Icons.edit_note_outlined,
      'medication_created' => Icons.medication_outlined,
      'member_joined' => Icons.person_add_alt_1_outlined,
      'representative_transferred' => Icons.manage_accounts_outlined,
      'member_left' => Icons.logout_rounded,
      'member_removed' => Icons.person_remove_outlined,
      _ => Icons.domain_disabled_outlined,
    };
    final message = switch (item.type) {
      'memo_created' => '가족이 새로운 메모를 남겼어요. 메모 메뉴에서 내용을 확인해 주세요.',
      'medication_created' => '새로운 약이 추가되었어요. 투약일지에서 복용 정보를 확인해 주세요.',
      'member_joined' => '새로운 가족이 함께하게 되었어요. 공간 설정에서 함께하는 가족을 확인할 수 있어요.',
      'representative_transferred' =>
        '돌봄 공간의 주보호자가 변경되었어요. 공간 설정에서 현재 역할을 확인해 주세요.',
      'member_left' => '가족이 돌봄 공간에서 나갔어요. 나간 가족은 이 공간에 접근할 수 없어요.',
      'member_removed' => '가족의 공간 참여가 종료되었어요. 참여가 종료된 가족은 이 공간에 접근할 수 없어요.',
      _ => '주보호자가 이 돌봄 공간을 삭제했습니다.\n이 공간은 더 이상 이용할 수 없습니다.',
    };
    final time = DateTime.tryParse(item.createdAt)?.toLocal();
    final timestamp = time == null
        ? item.createdAt
        : '${time.year}-${time.month.toString().padLeft(2, '0')}-${time.day.toString().padLeft(2, '0')} ${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}';
    return Dialog(
      backgroundColor: colors.background,
      surfaceTintColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      clipBehavior: Clip.antiAlias,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 440),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Container(
                color: colors.surface,
                padding: const EdgeInsets.fromLTRB(22, 22, 14, 20),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: 48,
                      height: 48,
                      decoration: BoxDecoration(
                        color: colors.sageLight,
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Icon(icon, color: colors.sageDark, size: 26),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            AppStrings.tr(
                              context,
                              item.isRoomDeletion ? '돌봄 공간 삭제 안내' : '새로운 소식',
                            ),
                            style: TextStyle(
                              fontSize: 12,
                              color: colors.textSecondary,
                            ),
                          ),
                          const SizedBox(height: 5),
                          Text(
                            AppStrings.tr(context, item.title),
                            style: TextStyle(
                              fontSize: 21,
                              height: 1.35,
                              fontWeight: FontWeight.w800,
                              color: colors.textPrimary,
                            ),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      tooltip: AppStrings.tr(context, '닫기'),
                      onPressed: () => Navigator.pop(context),
                      icon: const Icon(Icons.close),
                      color: colors.textSecondary,
                      visualDensity: VisualDensity.compact,
                    ),
                  ],
                ),
              ),
              Divider(height: 1, color: colors.border),
              Padding(
                padding: const EdgeInsets.all(22),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: colors.peachSoft,
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            Icons.home_outlined,
                            color: colors.sageDark,
                            size: 23,
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              AppStrings.format(context, '{0} 돌봄 공간', [
                                item.recipientName,
                              ]),
                              style: TextStyle(
                                fontSize: 16,
                                height: 1.4,
                                fontWeight: FontWeight.w700,
                                color: colors.textPrimary,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 20),
                    Text(
                      AppStrings.tr(context, message),
                      style: TextStyle(
                        fontSize: 15,
                        height: 1.7,
                        color: colors.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 20),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(
                          Icons.access_time_rounded,
                          size: 16,
                          color: colors.textSecondary,
                        ),
                        const SizedBox(width: 7),
                        Expanded(
                          child: Text(
                            timestamp,
                            style: TextStyle(
                              fontSize: 12,
                              height: 1.4,
                              color: colors.textSecondary,
                            ),
                          ),
                        ),
                      ],
                    ),
                    if (item.roomDeletedAt != null) ...[
                      const SizedBox(height: 10),
                      Text(
                        '${AppStrings.tr(context, '삭제 시각')}: ${item.roomDeletedAt!.replaceAll('T', ' ')}',
                        style: TextStyle(
                          fontSize: 12,
                          color: colors.textSecondary,
                        ),
                      ),
                    ],
                    const SizedBox(height: 24),
                    FilledButton(
                      onPressed: () => Navigator.pop(context),
                      style: FilledButton.styleFrom(
                        backgroundColor: colors.primary,
                        foregroundColor: AppColors.textPrimary,
                        minimumSize: const Size(0, 48),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                      ),
                      child: Text(
                        AppStrings.tr(context, '확인'),
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
