import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'english_strings.dart';

/// 표시는 번역하되 API 상태값·사용자 작성 내용은 변경하지 않는다.
class AppStrings {
  const AppStrings(this.locale);
  final Locale locale;
  static const supportedLocales = [Locale('ko', 'KR'), Locale('en', 'US')];
  static const delegate = _AppStringsDelegate();
  // 기존 독립 위젯·테스트에는 한국어를 기본값으로 제공한다.
  static bool isEnglish(BuildContext context) =>
      Localizations.of<AppStrings>(context, AppStrings)?.locale.languageCode ==
      'en';
  static String tr(BuildContext context, String source) {
    if (!isEnglish(context)) return source;
    final exact = englishStrings[source];
    if (exact != null) return exact;
    // 기존 UI에서 조합한 시스템 표시값(복약 시간 등)도 같은 사전을 사용한다.
    for (final entry in _templates) {
      final match = entry.pattern.firstMatch(source);
      if (match == null) continue;
      var text = entry.english;
      for (var i = 0; i < entry.indices.length; i++) {
        final value = match.group(i + 1)!;
        text = text.replaceAll(
          '{${entry.indices[i]}}',
          englishStrings[value] ?? value,
        );
      }
      return text;
    }
    return source;
  }

  static String format(
    BuildContext context,
    String template,
    List<Object?> args,
  ) {
    var translated = tr(context, template);
    if (isEnglish(context) && args.isNotEmpty && args.first == 1) {
      const singular = {
        'spaces': 'space',
        'notifications': 'notification',
        'invitations': 'invitation',
        'inquiries': 'inquiry',
        'notices': 'notice',
        'schedules': 'schedule',
        'likes': 'like',
        'entries': 'entry',
        'members': 'member',
      };
      for (final entry in singular.entries) {
        translated = translated.replaceAll(
          RegExp('\\b${entry.key}\\b'),
          entry.value,
        );
      }
    }
    // 치환된 사용자 문자열을 다시 해석하지 않는다(이름에 {1} 등이 있어도 그대로 보존).
    return translated.replaceAllMapped(RegExp(r'\{(\d+)\}'), (match) {
      final index = int.parse(match.group(1)!);
      return index < args.length
          ? args[index]?.toString() ?? ''
          : match.group(0)!;
    });
  }

  static String error(BuildContext context, String source) {
    final result = tr(context, source);
    if (isEnglish(context) &&
        result == source &&
        RegExp(r'[\uAC00-\uD7A3]').hasMatch(source)) {
      return 'Unable to complete the request. Please try again.';
    }
    return result;
  }

  static String monthYear(BuildContext context, DateTime date) =>
      isEnglish(context)
      ? MaterialLocalizations.of(context).formatMonthYear(date)
      : '${date.year}년 ${date.month}월';
  static String fullDate(BuildContext context, DateTime date) =>
      isEnglish(context)
      ? MaterialLocalizations.of(context).formatFullDate(date)
      : '${date.year}년 ${date.month}월 ${date.day}일 ${const ['월요일', '화요일', '수요일', '목요일', '금요일', '토요일', '일요일'][date.weekday - 1]}';
}

class _Template {
  _Template(String source, this.english) {
    final matches = RegExp(r'\{(\d+)\}').allMatches(source).toList();
    indices = [for (final match in matches) int.parse(match.group(1)!)];
    var offset = 0;
    var expression = '^';
    for (final match in matches) {
      expression +=
          '${RegExp.escape(source.substring(offset, match.start))}([\\s\\S]*?)';
      offset = match.end;
    }
    pattern = RegExp(
      expression + RegExp.escape(source.substring(offset)) + r'$',
    );
  }
  late final RegExp pattern;
  late final List<int> indices;
  final String english;
}

final _templates = [
  for (final entry in englishStrings.entries)
    if (entry.key.contains(RegExp(r'\{\d+\}')))
      _Template(entry.key, entry.value),
]..sort((a, b) => b.pattern.pattern.length.compareTo(a.pattern.pattern.length));

class _AppStringsDelegate extends LocalizationsDelegate<AppStrings> {
  const _AppStringsDelegate();
  @override
  bool isSupported(Locale locale) => ['ko', 'en'].contains(locale.languageCode);
  @override
  Future<AppStrings> load(Locale locale) =>
      SynchronousFuture(AppStrings(locale));
  @override
  bool shouldReload(_AppStringsDelegate old) => false;
}
