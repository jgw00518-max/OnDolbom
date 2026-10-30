import 'package:ondolbom/l10n/app_strings.dart';
import 'package:ondolbom/theme/app_theme.dart';
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
    this.floatingActionButton,
    this.onBack,
  });
  final String roomName;
  final String title;
  final Widget child;
  final Widget? action;
  final Widget? footer;
  final Widget? floatingActionButton;
  final VoidCallback? onBack;

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: AppColors.of(context).background,
    floatingActionButton: floatingActionButton,
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
              // 공통 AppBar를 사용해 좌우 버튼 너비와 관계없이 제목을 중앙에 배치한다.
              AppBar(
                primary: false,
                toolbarHeight: AppTheme.toolbarHeight,
                automaticallyImplyLeading: false,
                leadingWidth: 62,
                leading: onBack == null
                    ? null
                    : AppBackLeading(onPressed: onBack),
                title: Text(title),
                actions: action == null ? null : [action!],
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
            decoration: BoxDecoration(
              color: AppColors.of(context).peachSoft,
              shape: BoxShape.circle,
            ),
            child: Icon(
              Icons.person_outline_rounded,
              size: 24,
              color: AppColors.of(context).textPrimary,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  author,
                  style: TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w800,
                    color: AppColors.of(context).textPrimary,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  memoDate(date),
                  style: TextStyle(
                    fontSize: 11,
                    color: AppColors.of(context).textSecondary,
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
              Icon(
                Icons.favorite_border,
                size: 16,
                color: AppColors.of(context).sageDark,
              ),
              const SizedBox(width: 5),
              Text(
                AppStrings.format(context, "좋아요 {0}", [likes]),
                style: TextStyle(
                  fontSize: 12,
                  color: AppColors.of(context).sageDark,
                ),
              ),
            ],
          ),
    ],
  );
}
