import 'package:ondolbom/l10n/app_strings.dart';
import 'package:ondolbom/theme/app_colors.dart';
import 'package:ondolbom/view/widgets/app_back_button.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:ondolbom/model/family/family_room.dart';
import 'package:ondolbom/view/family_room/recipient_edit.dart';
import 'package:ondolbom/vm/family_room/family_room_notifier.dart';

class RecipientDetail extends ConsumerWidget {
  const RecipientDetail({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(familyRoomProvider);
    final room = state.selectedRoom;
    final participation = state.selectedParticipation;

    if (room == null || participation == null) {
      return Scaffold(
        appBar: AppBar(title: Text(AppStrings.tr(context, '대상자 정보'))),
        body: Center(child: Text(AppStrings.tr(context, '선택한 공간이 없습니다.'))),
      );
    }

    // 날짜만 표시한다.
    final birthDate = room.birthDate;
    final birthText = birthDate == null
        ? '미등록'
        : '${birthDate.year}-'
              '${birthDate.month.toString().padLeft(2, '0')}-'
              '${birthDate.day.toString().padLeft(2, '0')}';

    return Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: false,
        leadingWidth: 62,
        leading: const AppBackLeading(),
        centerTitle: true,
        title: Text(AppStrings.tr(context, '대상자 정보')),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 20),
            child: Container(
              padding: const EdgeInsets.all(11),
              decoration: BoxDecoration(
                color: AppColors.of(context).sageLight,
                borderRadius: BorderRadius.circular(16),
              ),
              child: Icon(
                Icons.person_outline,
                color: AppColors.of(context).sageDark,
              ),
            ),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 28, 20, 32),
        children: [
          // 제목과 수정 버튼
          Row(
            children: [
              Expanded(
                child: Text(
                  AppStrings.tr(context, '돌봄 대상자'),
                  style: TextStyle(fontSize: 25, fontWeight: FontWeight.w800),
                ),
              ),

              // 수정은 현재 공간의 주보호자에게만 표시한다.
              if (participation.isRepresentative)
                FilledButton(
                  onPressed: () => editAction(context, ref, room),
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
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                  ),
                  child: Text(AppStrings.tr(context, '수정')),
                ),
            ],
          ),
          const SizedBox(height: 16),

          // 대상자 정보 카드
          Card(
            color: AppColors.of(context).surface,
            elevation: 0,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(24),
              side: BorderSide(color: AppColors.of(context).border),
            ),
            margin: EdgeInsets.zero,
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    AppStrings.format(context, "{0} 님", [
                      room.careRecipientName,
                    ]),
                    style: const TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 28),

                  // 확정한 성별 코드에 맞춰 한글로 표시한다.
                  infoRow(
                    context,
                    AppStrings.tr(context, '성별'),
                    switch (room.gender) {
                      1 => AppStrings.tr(context, '남성'),
                      2 => AppStrings.tr(context, '여성'),
                      null => AppStrings.tr(context, '미등록'),
                      _ => AppStrings.tr(context, '확인 필요'),
                    },
                  ),
                  infoRow(context, AppStrings.tr(context, '생년월일'), birthText),
                  infoRow(
                    context,
                    AppStrings.tr(context, '특이사항'),
                    room.specialNotes,
                  ),
                  infoRow(
                    context,
                    AppStrings.tr(context, '돌봄 장소'),
                    room.careAddress,
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  } // build

  // ----- function -----

  // 같은 형태의 정보 행을 반복해서 사용한다.
  Widget infoRow(BuildContext context, String title, String? value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 20),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 100,
            child: Text(
              title,
              style: TextStyle(
                fontSize: 16,
                color: AppColors.of(context).textSecondary,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              value == null || value.trim().isEmpty
                  ? AppStrings.tr(context, '미등록')
                  : value,
              style: const TextStyle(fontSize: 16),
            ),
          ),
        ],
      ),
    );
  }

  // 편집 화면에서 저장하면 공간 정보를 다시 조회한다.
  Future<void> editAction(
    BuildContext context,
    WidgetRef ref,
    FamilyRoom room,
  ) async {
    final saved = await Navigator.push<bool>(
      context,
      MaterialPageRoute(builder: (_) => RecipientEdit(room: room)),
    );

    if (!context.mounted || saved != true) {
      return;
    }

    await ref.read(familyRoomProvider.notifier).fetchRooms();

    if (!context.mounted) {
      return;
    }

    final state = ref.read(familyRoomProvider);

    final message = state.errorMessage != null
        ? '저장은 완료되었지만 최신 정보를 불러오지 못했습니다. 공간 목록을 새로고침해 주세요.'
        : '대상자 정보를 수정했습니다.';

    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(AppStrings.error(context, message))));
  }
} // class
