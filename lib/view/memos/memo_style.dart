import 'package:flutter/material.dart';

const memoBackground = Color(0xFFFFFBF5);
const memoBrown = Color(0xFF936345);
const memoPeach = Color(0xFFE5AF8B);
const memoMuted = Color(0xFF807B73);

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
    backgroundColor: memoBackground,
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
                    const Text(
                      '온돌봄',
                      style: TextStyle(
                        fontSize: 27,
                        fontWeight: FontWeight.w900,
                        color: memoBrown,
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
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(24),
                          border: Border.all(color: const Color(0xFFECE6DE)),
                        ),
                        child: Text(
                          roomName,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 12,
                            color: memoMuted,
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
                        style: const TextStyle(
                          fontSize: 23,
                          fontWeight: FontWeight.w800,
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
  });
  final String author;
  final DateTime? date;
  final int likes;
  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(
        '$author · ${memoDate(date)}',
        style: const TextStyle(color: memoMuted, fontSize: 12),
      ),
      const SizedBox(height: 12),
      Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.favorite_border, size: 16, color: memoMuted),
          const SizedBox(width: 5),
          Text(
            '좋아요 $likes',
            style: const TextStyle(color: memoMuted, fontSize: 12),
          ),
        ],
      ),
    ],
  );
}
