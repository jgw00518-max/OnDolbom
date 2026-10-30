import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:ondolbom/model/family/family_room_onboarding_step.dart';
import 'package:ondolbom/theme/app_colors.dart';
import 'package:ondolbom/vm/auth/auth_vm.dart';
import 'package:ondolbom/vm/family_room/family_room_onboarding_vm.dart';

// 목록 위에 표시하므로 기존 Navigator·공간 선택 상태는 바뀌지 않는다.
class FamilyRoomOnboardingGate extends ConsumerStatefulWidget {
  const FamilyRoomOnboardingGate({super.key, required this.child});
  final Widget child;
  @override
  ConsumerState<FamilyRoomOnboardingGate> createState() =>
      _FamilyRoomOnboardingGateState();
}

class _FamilyRoomOnboardingGateState
    extends ConsumerState<FamilyRoomOnboardingGate> {
  bool _open = false;
  late final FamilyRoomOnboardingVm _vm;
  @override
  void initState() {
    super.initState();
    _vm = ref.read(familyRoomOnboardingProvider.notifier);
    _schedule();
  }

  @override
  void dispose() {
    if (_open) unawaited(Future<void>.microtask(_vm.release));
    super.dispose();
  }

  void _schedule() => WidgetsBinding.instance.addPostFrameCallback((_) {
    if (mounted) unawaited(_tryOpen());
  });
  Future<void> _tryOpen() async {
    final uid = ref.read(authUserProvider).asData?.value?.uid;
    if (uid == null || _open || ModalRoute.of(context)?.isCurrent == false) {
      return;
    }
    final vm = ref.read(familyRoomOnboardingProvider.notifier);
    if (!await vm.begin()) return;
    if (!mounted) {
      vm.release();
      return;
    }
    if (ref.read(authUserProvider).asData?.value?.uid != uid ||
        ModalRoute.of(context)?.isCurrent == false) {
      vm.release();
      return;
    }
    setState(() => _open = true);
  }

  void _finish() {
    if (!_open) return;
    unawaited(ref.read(familyRoomOnboardingProvider.notifier).finish());
    setState(() => _open = false);
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(authUserProvider, (previous, next) {
      if (previous?.asData?.value?.uid != next.asData?.value?.uid) {
        if (_open) {
          setState(() => _open = false);
          _vm.release();
        }
        _schedule();
      }
    });
    return PopScope(
      canPop: !_open,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop && _open) _finish();
      },
      child: Stack(
        fit: StackFit.expand,
        children: [
          ExcludeSemantics(excluding: _open, child: widget.child),
          if (_open) FamilyRoomOnboarding(onFinished: _finish),
        ],
      ),
    );
  }
}

class FamilyRoomOnboarding extends StatefulWidget {
  const FamilyRoomOnboarding({super.key, required this.onFinished});
  final VoidCallback onFinished;
  @override
  State<FamilyRoomOnboarding> createState() => _FamilyRoomOnboardingState();
}

class _FamilyRoomOnboardingState extends State<FamilyRoomOnboarding> {
  final _controller = PageController();
  late Future<List<FamilyRoomOnboardingStep>> _steps =
      FamilyRoomOnboardingStep.load();
  int _page = 0;
  @override
  void reassemble() {
    super.reassemble();
    // 핫 리로드 시 이전 모델 객체를 재사용하지 않고 새 안내 데이터를 읽는다.
    _steps = FamilyRoomOnboardingStep.load();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Material(
    color: AppColors.of(context).peachSoft,
    child: SafeArea(
      child: FutureBuilder(
        future: _steps,
        builder: (context, snapshot) {
          final steps = snapshot.data;
          if (snapshot.hasError ||
              steps == null ||
              snapshot.connectionState != ConnectionState.done) {
            return Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (snapshot.hasError)
                    Text(
                      '안내 화면을 불러오지 못했어요.',
                      style: TextStyle(
                        color: AppColors.of(context).textPrimary,
                      ),
                    )
                  else
                    const CircularProgressIndicator(),
                  TextButton(
                    onPressed: widget.onFinished,
                    child: const Text('건너뛰기'),
                  ),
                ],
              ),
            );
          }
          final last = _page == steps.length - 1;
          return Column(
            children: [
              Expanded(
                child: PageView.builder(
                  controller: _controller,
                  itemCount: steps.length,
                  onPageChanged: (page) => setState(() => _page = page),
                  itemBuilder: (context, index) =>
                      _OnboardingPage(step: steps[index], index: index),
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: Row(
                  children: [
                    Expanded(
                      flex: 2,
                      child: TextButton(
                        onPressed: widget.onFinished,
                        style: TextButton.styleFrom(
                          foregroundColor: AppColors.of(context).sageDark,
                          minimumSize: const Size(0, 48),
                        ),
                        child: const FittedBox(child: Text('건너뛰기')),
                      ),
                    ),
                    Expanded(
                      flex: 3,
                      child: Semantics(
                        label: '${steps.length}페이지 중 ${_page + 1}페이지',
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              '${_page + 1} / ${steps.length}',
                              style: TextStyle(
                                color: AppColors.of(context).textSecondary,
                                fontSize: 11,
                              ),
                            ),
                            const SizedBox(height: 4),
                            ExcludeSemantics(
                              child: FittedBox(
                                fit: BoxFit.scaleDown,
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    for (var i = 0; i < steps.length; i++)
                                      AnimatedContainer(
                                        duration: const Duration(
                                          milliseconds: 180,
                                        ),
                                        margin: const EdgeInsets.symmetric(
                                          horizontal: 3,
                                        ),
                                        width: i == _page ? 16 : 5,
                                        height: 5,
                                        decoration: BoxDecoration(
                                          color: i == _page
                                              ? AppColors.of(context).sageDark
                                              : AppColors.of(context).border,
                                          borderRadius: BorderRadius.circular(
                                            8,
                                          ),
                                        ),
                                      ),
                                  ],
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    Expanded(
                      flex: 2,
                      child: TextButton(
                        onPressed: () {
                          if (last) {
                            widget.onFinished();
                          } else {
                            _controller.nextPage(
                              duration: const Duration(milliseconds: 260),
                              curve: Curves.easeOut,
                            );
                          }
                        },
                        style: TextButton.styleFrom(
                          foregroundColor: AppColors.of(context).sageDark,
                          minimumSize: const Size(0, 48),
                        ),
                        child: FittedBox(child: Text(last ? '시작하기' : '다음')),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    ),
  );
}

class _OnboardingPage extends StatelessWidget {
  const _OnboardingPage({required this.step, required this.index});
  final FamilyRoomOnboardingStep step;
  final int index;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, box) {
      final frame = _imageFrame(box.biggest);
      final target = _targetRect(step.target, box.biggest);
      const gap = 16.0;
      final above = math.max(0.0, target.top - frame.top - gap);
      final below = math.max(0.0, frame.bottom - target.bottom - gap);
      final useAbove = above >= below;
      // 강조 영역 위·아래 중 넓은 쪽에 설명을 놓아 영역과 겹치지 않게 한다.
      final captionTop = useAbove ? frame.top : target.bottom + gap;
      final captionHeight = useAbove ? above : below;
      return Stack(
        fit: StackFit.expand,
        children: [
          Positioned.fromRect(
            rect: frame,
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: AppColors.of(context).surface,
                borderRadius: BorderRadius.circular(20),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.12),
                    blurRadius: 20,
                    offset: const Offset(0, 6),
                  ),
                ],
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(20),
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    Semantics(
                      label: '실제 앱 화면: ${step.title}',
                      image: true,
                      child: Image.asset(
                        step.image,
                        key: ValueKey('onboarding-image-$index'),
                        fit: BoxFit.contain,
                        excludeFromSemantics: true,
                        errorBuilder: (context, error, stack) =>
                            const ColoredBox(color: Colors.black),
                      ),
                    ),
                    IgnorePointer(
                      child: CustomPaint(
                        painter: _SpotlightPainter(
                          step.target,
                          step.targetRadius ?? 20,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          Positioned(
            left: frame.left + 16,
            right: box.maxWidth - frame.right + 16,
            top: captionTop,
            height: captionHeight,
            child: Align(
              alignment: useAbove ? Alignment.bottomLeft : Alignment.topLeft,
              child: SingleChildScrollView(
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 16,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.42),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        'STEP ${index + 1}',
                        style: const TextStyle(
                          color: AppColors.primary,
                          fontSize: 13,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 1.5,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        step.title,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 22,
                          height: 1.4,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 10),
                      Text(
                        step.description,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 16,
                          height: 1.65,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      );
    },
  );
}

// 원본 화면 전체를 같은 비율로 축소한다. 잘라내거나 가로·세로를 따로 늘리지 않는다.
Rect _imageFrame(Size size) {
  const original = Size(390, 844);
  final width = math.max(0.0, size.width - 48);
  final height = math.max(0.0, size.height - 24);
  final scale = math.min(width / original.width, height / original.height);
  final image = Size(original.width * scale, original.height * scale);
  return Rect.fromLTWH(
    (size.width - image.width) / 2,
    (size.height - image.height) / 2,
    image.width,
    image.height,
  );
}

Rect _targetRect(Rect target, Size size) {
  final frame = _imageFrame(size);
  return Rect.fromLTWH(
    frame.left + target.left * frame.width,
    frame.top + target.top * frame.height,
    target.width * frame.width,
    target.height * frame.height,
  ).intersect(Offset.zero & size);
}

class _SpotlightPainter extends CustomPainter {
  const _SpotlightPainter(this.target, this.sourceRadius);
  final Rect target;
  final double? sourceRadius;
  @override
  void paint(Canvas canvas, Size size) {
    final rounded = RRect.fromRectAndRadius(
      Rect.fromLTWH(
        target.left * size.width,
        target.top * size.height,
        target.width * size.width,
        target.height * size.height,
      ).intersect(Offset.zero & size),
      Radius.circular((sourceRadius ?? 20) * size.width / 390),
    );
    final veil = Path()
      ..fillType = PathFillType.evenOdd
      ..addRect(Offset.zero & size)
      ..addRRect(rounded);
    canvas.drawPath(
      veil,
      Paint()..color = Colors.black.withValues(alpha: 0.72),
    );
  }

  @override
  bool shouldRepaint(_SpotlightPainter old) =>
      old.target != target || old.sourceRadius != sourceRadius;
}
