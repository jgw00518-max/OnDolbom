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
    final state = ref.watch(familyRoomProvider);
    final room = state.selectedRoom;

    if (room == null) {
      return Scaffold(
        drawer: const AccountDrawer(),
        appBar: AppBar(
          automaticallyImplyLeading: false,
          title: const Text('돌봄 공간'),
          leading: const AccountMenuButton(),
        ),
        body: const Center(child: Text('공간을 선택해 주세요.')),
      );
    }

    return Scaffold(
      drawer: AccountDrawer(familyRoomId: room.familyRoomId),
      appBar: AppBar(
        automaticallyImplyLeading: false,
        centerTitle: true,
        foregroundColor: AppColors.textPrimary,
        title: const Text(
          '온돌봄',
          style: TextStyle(fontSize: 24, fontWeight: FontWeight.w800),
        ),
        leading: const AccountMenuButton(),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 32),
        children: [
          // 공간 정보와 장식만 표시하며 기존 데이터 조회 흐름은 변경하지 않는다.
          FamilyRoomLabel(name: '${room.careRecipientName} 님의 돌봄 공간'),
          const SizedBox(height: 18),
          LayoutBuilder(
            builder: (context, constraints) {
              final stacked =
                  constraints.maxWidth < 300 ||
                  MediaQuery.textScalerOf(context).scale(16) > 20;
              const copy = Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '나의 일상에,',
                    style: TextStyle(
                      fontSize: 30,
                      fontWeight: FontWeight.w800,
                      color: AppColors.textPrimary,
                    ),
                  ),
                  Text(
                    '안심을 더하다',
                    style: TextStyle(
                      fontSize: 30,
                      fontWeight: FontWeight.w800,
                      color: AppColors.primary,
                    ),
                  ),
                  SizedBox(height: 12),
                  Text(
                    '소중한 사람의 오늘도,\n온돌봄이 함께합니다.',
                    style: TextStyle(
                      fontSize: 14,
                      height: 1.6,
                      color: AppColors.textSecondary,
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
                return const Column(
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
              return const Row(
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

          const Text(
            '돌봄 메뉴',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 16),

          // 첫 번째 메뉴 줄
          Row(
            children: [
              menuButton(
                '투약일지',
                Icons.medication_outlined,
                () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => const MedicationListView(),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              menuButton(
                '실시간 채팅',
                Icons.chat_bubble_outline,
                () => Navigator.of(context).push(
                  MaterialPageRoute<void>(builder: (_) => const ChatView()),
                ),
              ),
              const SizedBox(width: 10),
              menuButton(
                '메모',
                Icons.edit_outlined,
                () => Navigator.of(context).push(
                  MaterialPageRoute<void>(builder: (_) => const MemoListView()),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),

          // 두 번째 메뉴 줄
          Row(
            children: [
              menuButton(
                '일정',
                Icons.calendar_month_outlined,
                () => scheduleAction(context, room.familyRoomId),
              ),
              const SizedBox(width: 10),
              menuButton(
                '대상자 정보',
                Icons.people_outline,
                () => recipientAction(context),
              ),
              const SizedBox(width: 10),

              // 모든 역할에서 같은 위치로 공간 관리 기능에 접근한다.
              menuButton(
                '공간 설정',
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

          // 가족 관리 기능은 공간 설정으로 모으고 일정 카드를 메뉴 아래에 배치한다.
          Card(
            color: AppColors.surface,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(22),
              side: const BorderSide(color: AppColors.border),
            ),
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Expanded(
                        child: Text(
                          '오늘의 일정',
                          style: TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                      TextButton(
                        onPressed: () =>
                            scheduleAction(context, room.familyRoomId),
                        child: const Text('전체 일정'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  const Row(
                    children: [
                      Icon(
                        Icons.calendar_month_outlined,
                        color: AppColors.sageDark,
                      ),
                      SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          '일정 조회 기능 연결 전입니다.',
                          style: TextStyle(
                            fontSize: 13,
                            color: AppColors.textSecondary,
                          ),
                        ),
                      ),
                    ],
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

  // 반복되는 메뉴 모양을 만든다.
  Widget menuButton(String title, IconData icon, VoidCallback action) {
    return Expanded(
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 106),
        child: OutlinedButton(
          onPressed: action,
          style: OutlinedButton.styleFrom(
            padding: const EdgeInsets.all(8),
            backgroundColor: AppColors.surface,
            foregroundColor: AppColors.textPrimary,
            side: const BorderSide(color: AppColors.border),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(20),
            ),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: title == '일정' || title == '실시간 채팅' || title == '공간 설정'
                      ? AppColors.sageLight
                      : AppColors.peachSoft,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(icon, size: 23, color: AppColors.sageDark),
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
  void scheduleAction(BuildContext context, String familyRoomId) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ScheduleList(familyRoomId: familyRoomId),
      ),
    );
  }

  // 아직 연결하지 않은 기능을 안내한다.
  void preparingAction(BuildContext context) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('아직 연결하지 않은 기능입니다.')));
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
