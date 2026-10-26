import 'package:flutter/material.dart';

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
    this.onBack,
  });
  final String roomName;
  final String title;
  final Widget child;
  final Widget? action;
  final VoidCallback? onBack;

  @override
  Widget build(BuildContext context) => Scaffold(
    body: SafeArea(
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 640),
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 18, 20, 12),
                child: Row(
                  children: [
                    Text(
                      '온돌봄',
                      style:
                          Theme.of(context).appBarTheme.titleTextStyle ??
                          Theme.of(context).textTheme.headlineSmall?.copyWith(
                            color: Theme.of(context).colorScheme.primary,
                            fontWeight: FontWeight.bold,
                          ),
                    ),
                    const SizedBox(width: 12),
                    Flexible(
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 10,
                        ),
                        decoration: BoxDecoration(
                          color: Theme.of(
                            context,
                          ).colorScheme.secondaryContainer,
                          borderRadius: BorderRadius.circular(24),
                          border: Border.all(
                            color: Theme.of(context).colorScheme.outline,
                          ),
                        ),
                        child: Text(
                          roomName,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 12,
                            color: Theme.of(
                              context,
                            ).colorScheme.onSecondaryContainer,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 20,
                  vertical: 8,
                ),
                child: Row(
                  children: [
                    if (onBack != null) ...[
                      IconButton.outlined(
                        onPressed: onBack,
                        tooltip: '이전 화면',
                        icon: const Icon(Icons.chevron_left),
                      ),
                      const SizedBox(width: 10),
                    ],
                    Expanded(
                      child: Text(
                        title,
                        style:
                            Theme.of(context).appBarTheme.titleTextStyle ??
                            Theme.of(context).textTheme.titleLarge?.copyWith(
                              color: Theme.of(context).colorScheme.primary,
                            ),
                      ),
                    ),
                    ?action,
                  ],
                ),
              ),
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 20),
                child: Divider(),
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
      Text(
        '$author · ${memoDate(date)}',
        style: TextStyle(
          color: Theme.of(context).colorScheme.onSurfaceVariant,
          fontSize: 12,
        ),
      ),
      const SizedBox(height: 12),
      likeButton ??
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.favorite_border,
                size: 16,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
              const SizedBox(width: 5),
              Text(
                '좋아요 $likes',
                style: TextStyle(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                  fontSize: 12,
                ),
              ),
            ],
          ),
    ],
  );
}
