import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:ondolbom/theme/app_colors.dart';
import 'package:ondolbom/vm/family_room/family_member_vm.dart';

// 현재 참여 가족 API를 사용하며 임의의 이름이나 인원은 표시하지 않는다.
class FamilyRoomMemberSummary extends ConsumerWidget {
  const FamilyRoomMemberSummary({super.key, required this.familyRoomId});
  final String familyRoomId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final members = ref.watch(familyMembersProvider(familyRoomId));
    return members.when(
      loading: () => const Text(
        '참여 가족 확인 중',
        style: TextStyle(fontSize: 11, color: AppColors.textSecondary),
      ),
      error: (_, _) => InkWell(
        onTap: () => ref.invalidate(familyMembersProvider(familyRoomId)),
        child: const Padding(
          padding: EdgeInsets.symmetric(vertical: 6),
          child: Text(
            '참여 가족 다시 조회',
            style: TextStyle(fontSize: 11, color: AppColors.sageDark),
          ),
        ),
      ),
      data: (people) {
        final preview = people.take(3).toList();
        return Wrap(
          spacing: 8,
          runSpacing: 6,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            if (preview.isNotEmpty)
              SizedBox(
                width: 26 + (preview.length - 1) * 18,
                height: 26,
                child: Stack(
                  children: [
                    for (var index = 0; index < preview.length; index++)
                      Positioned(
                        left: index * 18,
                        child: Tooltip(
                          message:
                              preview[index].name?.trim().isNotEmpty == true
                              ? preview[index].name!
                              : '가족',
                          child: Container(
                            width: 26,
                            height: 26,
                            alignment: Alignment.center,
                            decoration: BoxDecoration(
                              color: [
                                AppColors.sage,
                                AppColors.peachLight,
                                AppColors.peachSoft,
                              ][index],
                              shape: BoxShape.circle,
                              border: Border.all(
                                color: AppColors.surface,
                                width: 2,
                              ),
                            ),
                            child: Text(
                              preview[index].name?.trim().isNotEmpty == true
                                  ? preview[index].name!.trim().characters.first
                                  : '가',
                              style: const TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.w700,
                                color: AppColors.sageDark,
                              ),
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            Text(
              '${people.length}명이 함께하고 있어요',
              style: const TextStyle(
                fontSize: 11,
                color: AppColors.textSecondary,
              ),
            ),
          ],
        );
      },
    );
  }
}
