import 'package:ondolbom/view/widgets/family_room_label.dart';
import 'package:ondolbom/view/widgets/app_back_button.dart';
import 'package:flutter/material.dart';
import 'package:ondolbom/theme/app_colors.dart';

String memoDate(DateTime? value) {
  if (value == null) return '작성 시간 없음';
  final time = value.toLocal();
  final period = time.hour < 12 ? '오전' : '오후';
  final hour = time.hour % 12 == 0 ? 12 : time.hour % 12;
  return '${time.month}.${time.day} $period $hour:${time.minute.toString().padLeft(2, '0')}';
}

class MemoLayout extends StatelessWidget {
  const MemoLayout({
    super.key,
    required this.roomName,
    required this.title,
    required this.child,
    this.action,
    this.footer,
    this.onBack,
  });
  final String roomName;
  final String title;
  final Widget child;
  final Widget? action;
  final Widget? footer;
  final VoidCallback? onBack;

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: AppColors.background,
    bottomNavigationBar: footer == null
        ? null
        : SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
              child: Center(
                heightFactor: 1,
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 600),
                  child: footer,
                ),
              ),
            ),
          ),
    body: SafeArea(
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 640),
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(14, 12, 20, 8),
                child: Row(
                  children: [
                    if (onBack != null) ...[
                      AppBackButton(onPressed: onBack),
                      const SizedBox(width: 12),
                    ] else
                      const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        title,
                        style: const TextStyle(
                          fontSize: 24,
                          fontWeight: FontWeight.w800,
                          color: AppColors.textPrimary,
                        ),
                      ),
                    ),
                    ?action,
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
                child: FamilyRoomLabel(name: roomName),
              ),
              Expanded(child: child),
            ],
          ),
        ),
      ),
    ),
  );
}

class MemoMetadata extends StatelessWidget {
  const MemoMetadata({
    super.key,
    required this.author,
    required this.date,
    required this.likes,
    this.likeButton,
  });
  final String author;
  final DateTime? date;
  final int likes;
  final Widget? likeButton;
  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: const BoxDecoration(
              color: AppColors.peachSoft,
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.person_outline_rounded,
              size: 24,
              color: AppColors.textPrimary,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  author,
                  style: const TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w800,
                    color: AppColors.textPrimary,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  memoDate(date),
                  style: const TextStyle(
                    fontSize: 11,
                    color: AppColors.textSecondary,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
      const SizedBox(height: 8),
      likeButton ??
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                Icons.favorite_border,
                size: 16,
                color: AppColors.sageDark,
              ),
              const SizedBox(width: 5),
              Text(
                '좋아요 $likes',
                style: const TextStyle(fontSize: 12, color: AppColors.sageDark),
              ),
            ],
          ),
    ],
  );
}
