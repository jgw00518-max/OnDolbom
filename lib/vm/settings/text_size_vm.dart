import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:ondolbom/model/settings/text_size_preferences.dart';

class TextSizeSetting {
  const TextSizeSetting(this.size, {this.saving = false, this.error});
  final AppTextSize size;
  final bool saving;
  final String? error;
}

final textSizeProvider = AsyncNotifierProvider<TextSizeVm, TextSizeSetting>(
  TextSizeVm.new,
  retry: (_, _) => null,
);

class TextSizeVm extends AsyncNotifier<TextSizeSetting> {
  @override
  Future<TextSizeSetting> build() async =>
      TextSizeSetting(await ref.watch(textSizePreferencesProvider).read());

  Future<void> select(AppTextSize size) async {
    final previous = state.asData?.value;
    if (previous == null ||
        previous.saving ||
        (previous.size == size && previous.error == null)) {
      return;
    }
    state = AsyncData(TextSizeSetting(previous.size, saving: true));
    try {
      // 저장 성공 후에만 전역 크기를 바꿔 저장 실패와 실제 선택값이 어긋나지 않게 한다.
      await ref.read(textSizePreferencesProvider).write(size);
      if (ref.mounted) state = AsyncData(TextSizeSetting(size));
    } catch (_) {
      if (ref.mounted) {
        state = AsyncData(
          TextSizeSetting(
            previous.size,
            error: '글씨 크기를 저장하지 못했습니다. 다시 선택해 주세요.',
          ),
        );
      }
    }
  }
}
