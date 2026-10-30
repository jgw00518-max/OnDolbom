import 'package:ondolbom/vm/activity/activity_vm.dart';
import 'package:ondolbom/l10n/app_strings.dart';
import 'package:ondolbom/view/family_room/today_schedule_card.dart';
import 'package:ondolbom/vm/schedules/schedule_vm.dart';
import 'package:ondolbom/vm/chats/chat_notifications_vm.dart';
import 'package:ondolbom/view/family_room/space_switcher_button.dart';
import 'package:ondolbom/view/family_room/space_settings_view.dart';
import 'package:ondolbom/view/widgets/family_room_label.dart';
import 'package:ondolbom/theme/app_colors.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:ondolbom/view/medications/medication_list_view.dart';
import 'package:ondolbom/view/chats/chat_view.dart';
import 'package:ondolbom/view/memos/memo_list_view.dart';
import 'package:ondolbom/view/recipient_detail.dart';
import 'package:ondolbom/view/schedules/schedule_list.dart';
import 'package:ondolbom/vm/family_room/family_room_notifier.dart';
import 'package:ondolbom/view/widgets/account_drawer.dart';

class FamilyRoomHome extends ConsumerWidget {
  const FamilyRoomHome({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.listen(familyRoomProvider, (previous, next) {
      if (previous?.selectedRoomId != next.selectedRoomId ||
          (previous?.isLoading == true && !next.isLoading)) {
        ref.invalidate(chatUnreadProvider);
      }
    });
    final state = ref.watch(familyRoomProvider);
    final room = state.selectedRoom;
    final activity = ref.watch(activityProvider);
    final chatCounts = ref.watch(chatUnreadProvider).asData?.value;

    if (room == null) {
      return Scaffold(
        drawer: const AccountDrawer(),
        appBar: AppBar(
          automaticallyImplyLeading: false,
          title: Text(AppStrings.tr(context, '돌봄 공간')),
          leading: const AccountMenuButton(),
        ),
        body: Center(child: Text(AppStrings.tr(context, '공간을 선택해 주세요.'))),
      );
    }

    return Scaffold(
      drawer: AccountDrawer(familyRoomId: room.familyRoomId),
      appBar: AppBar(
        automaticallyImplyLeading: false,
        centerTitle: true,
        foregroundColor: AppColors.of(context).textPrimary,
        title: Text(
          AppStrings.tr(context, '온돌봄'),
          style: TextStyle(fontSize: 24, fontWeight: FontWeight.w800),
        ),
        leading: const AccountMenuButton(),
      ),
      floatingActionButton: const SpaceSwitcherButton(),
      body: ListView(
        // 마지막 일정 카드가 이동 버튼에 가려지지 않도록 아래 여백을 확보한다.
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 112),
        children: [
          // 공간 정보와 장식만 표시하며 기존 데이터 조회 흐름은 변경하지 않는다.
          FamilyRoomLabel(name: '${room.careRecipientName} 님의 돌봄 공간'),
          const SizedBox(height: 18),
          LayoutBuilder(
            builder: (context, constraints) {
              final stacked =
                  constraints.maxWidth < 300 ||
                  MediaQuery.textScalerOf(context).scale(16) > 20;
              final copy = Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    AppStrings.tr(context, '나의 일상에,'),
                    style: TextStyle(
                      fontSize: 30,
                      fontWeight: FontWeight.w800,
                      color: AppColors.of(context).textPrimary,
                    ),
                  ),
                  Text(
                    AppStrings.tr(context, '안심을 더하다'),
                    style: TextStyle(
                      fontSize: 30,
                      fontWeight: FontWeight.w800,
                      color: AppColors.of(context).primary,
                    ),
                  ),
                  SizedBox(height: 12),
                  Text(
                    AppStrings.tr(context, '소중한 사람의 오늘도,\n온돌봄이 함께합니다.'),
                    style: TextStyle(
                      fontSize: 14,
                      height: 1.6,
                      color: AppColors.of(context).textSecondary,
                    ),
                  ),
                ],
              );
              const illustration = ExcludeSemantics(
                child: CustomPaint(
                  size: Size(104, 145),
                  painter: _WelcomePainter(),
                ),
              );
              if (stacked) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    copy,
                    Align(
                      alignment: Alignment.centerRight,
                      child: illustration,
                    ),
                  ],
                );
              }
              return Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Expanded(child: copy),
                  SizedBox(width: 8),
                  illustration,
                ],
              );
            },
          ),
          const SizedBox(height: 26),

          Text(
            AppStrings.tr(context, '돌봄 메뉴'),
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 16),

          // 첫 번째 메뉴 줄
          Row(
            children: [
              menuButton(
                context,
                AppStrings.tr(context, '투약일지'),
                Icons.medication_outlined,
                () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => const MedicationListView(),
                  ),
                ),
                hasNews: activity
                    .menuIds(room.familyRoomId, 'medications')
                    .isNotEmpty,
              ),
              const SizedBox(width: 10),
              menuButton(
                context,
                AppStrings.tr(context, '실시간 채팅'),
                Icons.chat_bubble_outline,
                () => Navigator.of(context)
                    .push(
                      MaterialPageRoute<void>(builder: (_) => const ChatView()),
                    )
                    .then((_) {
                      if (context.mounted) ref.invalidate(chatUnreadProvider);
                    }),
                badge: chatCounts?[room.familyRoomId] ?? 0,
              ),
              const SizedBox(width: 10),
              menuButton(
                context,
                AppStrings.tr(context, '메모'),
                Icons.edit_outlined,
                () => Navigator.of(context).push(
                  MaterialPageRoute<void>(builder: (_) => const MemoListView()),
                ),
                hasNews: activity
                    .menuIds(room.familyRoomId, 'memos')
                    .isNotEmpty,
              ),
            ],
          ),
          const SizedBox(height: 12),

          // 두 번째 메뉴 줄
          Row(
            children: [
              menuButton(
                context,
                AppStrings.tr(context, '일정'),
                Icons.calendar_month_outlined,
                () => scheduleAction(context, ref, room.familyRoomId),
                hasNews: activity
                    .menuIds(room.familyRoomId, 'schedules')
                    .isNotEmpty,
              ),
              const SizedBox(width: 10),
              menuButton(
                context,
                AppStrings.tr(context, '대상자 정보'),
                Icons.people_outline,
                () => recipientAction(context),
              ),
              const SizedBox(width: 10),

              // 모든 역할에서 같은 위치로 공간 관리 기능에 접근한다.
              menuButton(
                context,
                AppStrings.tr(context, '공간 설정'),
                Icons.settings_outlined,
                () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => const SpaceSettingsView(),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 28),
          TodayScheduleCard(
            key: ValueKey(room.familyRoomId),
            familyRoomId: room.familyRoomId,
          ),
        ],
      ),
    );
  } // build

  // ----- function -----

  // 반복되는 메뉴 모양을 만든다.
  Widget menuButton(
    BuildContext context,
    String title,
    IconData icon,
    VoidCallback action, {
    int badge = 0,
    bool hasNews = false,
  }) {
    return Expanded(
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 106),
        child: OutlinedButton(
          onPressed: action,
          style: OutlinedButton.styleFrom(
            padding: const EdgeInsets.all(8),
            backgroundColor: AppColors.of(context).surface,
            foregroundColor: AppColors.of(context).textPrimary,
            side: BorderSide(color: AppColors.of(context).border),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(20),
            ),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // 배지는 고정 크기 아이콘 바깥에 겹쳐 표시해 그림의 크기·중심을 유지한다.
              Badge(
                isLabelVisible: badge > 0 || hasNews,
                label: badge > 0 ? Text(badge > 99 ? '99+' : '$badge') : null,
                backgroundColor: hasNews
                    ? AppColors.notificationDot
                    : AppColors.of(context).primary,
                textColor: AppColors.of(context).textPrimary,
                child: Container(
                  width: 40,
                  height: 40,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color:
                        title == '일정' || title == '실시간 채팅' || title == '공간 설정'
                        ? AppColors.of(context).sageLight
                        : AppColors.of(context).peachSoft,
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Icon(
                    icon,
                    size: 23,
                    color: AppColors.of(context).sageDark,
                  ),
                ),
              ),
              const SizedBox(height: 9),
              Text(
                title,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // 대상자 정보 화면으로 이동한다.
  void recipientAction(BuildContext context) {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const RecipientDetail()),
    );
  }

  // 모든 참여 가족이 일정 달력·목록으로 이동한다.
  Future<void> scheduleAction(
    BuildContext context,
    WidgetRef ref,
    String familyRoomId,
  ) async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ScheduleList(familyRoomId: familyRoomId),
      ),
    );
    if (!context.mounted) return;
    final now = DateTime.now();
    ref.invalidate(
      scheduleListProvider((
        familyRoomId: familyRoomId,
        year: now.year,
        month: now.month,
      )),
    );
  }

  // 아직 연결하지 않은 기능을 안내한다.
  void preparingAction(BuildContext context) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(AppStrings.tr(context, '아직 연결하지 않은 기능입니다.'))),
    );
  }
}

/// Figma의 햇살·새싹 장식을 외부 이미지 없이 그립니다.
class _WelcomePainter extends CustomPainter {
  const _WelcomePainter();

  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.scale(size.width / 112, size.height / 156);
    final paint = Paint()..isAntiAlias = true;
    void oval(Rect rect, Color color) {
      paint
        ..style = PaintingStyle.fill
        ..color = color;
      canvas.drawOval(rect, paint);
    }

    void shape(Path path, Color color) {
      paint
        ..style = PaintingStyle.fill
        ..color = color;
      canvas.drawPath(path, paint);
    }

    void line(Path path, Color color, double width) {
      paint
        ..style = PaintingStyle.stroke
        ..color = color
        ..strokeWidth = width
        ..strokeCap = StrokeCap.round;
      canvas.drawPath(path, paint);
    }

    oval(const Rect.fromLTWH(14, 40, 94, 102), AppColors.peachSoft);
    oval(const Rect.fromLTWH(66, 10, 36, 36), const Color(0xA6F9AE89));
    line(
      Path()
        ..moveTo(84, 2)
        ..lineTo(84, 7)
        ..moveTo(109, 28)
        ..lineTo(104, 28)
        ..moveTo(64, 8)
        ..lineTo(68, 12),
      const Color(0x99F9AE89),
      2,
    );
    line(
      Path()
        ..moveTo(59, 131)
        ..cubicTo(58, 103, 60, 79, 74, 51),
      const Color(0xFFA8B39B),
      2.5,
    );
    shape(
      Path()
        ..moveTo(65, 92)
        ..cubicTo(45, 91, 33, 78, 36, 65)
        ..cubicTo(53, 65, 65, 74, 65, 92)
        ..close(),
      const Color(0xFFCDD6C2),
    );
    shape(
      Path()
        ..moveTo(64, 100)
        ..cubicTo(81, 100, 94, 89, 93, 75)
        ..cubicTo(77, 74, 64, 83, 64, 100)
        ..close(),
      const Color(0xFFB5C4A8),
    );
    shape(
      Path()
        ..moveTo(70, 72)
        ..cubicTo(56, 68, 48, 56, 52, 45)
        ..cubicTo(65, 48, 72, 57, 70, 72)
        ..close(),
      const Color(0xFFE0E6D8),
    );
    shape(
      Path()
        ..moveTo(73, 65)
        ..cubicTo(86, 62, 95, 52, 92, 42)
        ..cubicTo(79, 43, 72, 52, 73, 65)
        ..close(),
      const Color(0xFFC5D1B9),
    );
    shape(
      Path()
        ..moveTo(45, 122)
        ..lineTo(75, 122)
        ..lineTo(70, 144)
        ..lineTo(50, 144)
        ..close(),
      const Color(0xFFEAC8B2),
    );
    line(
      Path()
        ..moveTo(43, 122)
        ..lineTo(77, 122),
      const Color(0xFFD5AA90),
      3,
    );
    oval(const Rect.fromLTWH(30, 144, 60, 8), const Color(0x73EADBD2));
    oval(const Rect.fromLTWH(18, 43, 6, 6), const Color(0xFFEAC8B2));
    oval(const Rect.fromLTWH(97.5, 113.5, 5, 5), const Color(0xFFC5D1B9));
    shape(
      Path()
        ..moveTo(13, 104)
        ..lineTo(16, 107)
        ..lineTo(13, 110)
        ..lineTo(10, 107)
        ..close(),
      const Color(0x99F9AE89),
    );
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _WelcomePainter oldDelegate) => false;
}
