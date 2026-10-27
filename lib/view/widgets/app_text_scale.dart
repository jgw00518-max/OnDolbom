import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:ondolbom/model/settings/text_size_preferences.dart';
import 'package:ondolbom/vm/settings/text_size_vm.dart';

/// 시스템의 비선형 확대 방식을 그대로 사용한 뒤 앱의 배율을 추가 적용한다.
class AppTextScaler extends TextScaler {
  const AppTextScaler(this.system, this.factor);
  final TextScaler system;
  final double factor;
  @override
  double scale(double fontSize) => system.scale(fontSize) * factor;
  @override
  double get textScaleFactor => scale(14) / 14;
  @override
  bool operator ==(Object other) =>
      other is AppTextScaler &&
      other.system == system &&
      other.factor == factor;
  @override
  int get hashCode => Object.hash(system, factor);
}

class AppTextScale extends ConsumerWidget {
  const AppTextScale({super.key, required this.child});
  final Widget child;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final size =
        ref.watch(textSizeProvider).asData?.value.size ?? AppTextSize.medium;
    final media = MediaQuery.of(context);
    return MediaQuery(
      data: media.copyWith(
        textScaler: AppTextScaler(media.textScaler, size.factor),
      ),
      child: child,
    );
  }
}
