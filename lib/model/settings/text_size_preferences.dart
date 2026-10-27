import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

enum AppTextSize {
  small('작게', 0.9),
  medium('보통', 1.0),
  large('크게', 1.2);

  const AppTextSize(this.label, this.factor);
  final String label;
  final double factor;
}

final textSizePreferencesProvider = Provider<TextSizePreferences>(
  (ref) => TextSizePreferences(),
);

/// 로그인 여부와 관계없이 같은 기기에서 사용하는 글씨 크기만 보관한다.
class TextSizePreferences {
  static const key = 'appearance.text_size';
  SharedPreferencesAsync get _preferences => SharedPreferencesAsync();

  Future<AppTextSize> read() async {
    final stored = await _preferences.getString(key);
    return AppTextSize.values.firstWhere(
      (value) => value.name == stored,
      orElse: () => AppTextSize.medium,
    );
  }

  Future<void> write(AppTextSize size) =>
      _preferences.setString(key, size.name);
}
