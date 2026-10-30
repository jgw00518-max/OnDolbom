# 언어 설정

개인 설정 → 언어 설정에서 한국어·English를 선택합니다. 열린 화면에 즉시 반영되며 기기에 저장되어 로그아웃·앱 재실행 후에도 유지됩니다. 기본값은 한국어입니다.

- `lib/model/settings/locale_preferences.dart`: 기기별 언어 저장.
- `lib/vm/settings/locale_vm.dart`: 저장 성공 후 언어 전환, 저장 실패 시 기존 언어 유지.
- `lib/main.dart`: 앱 시작 시 복원하고 Material·Cupertino 날짜 선택기에도 언어 전달.
- `lib/l10n/app_strings.dart`, `english_strings.dart`: 공통 문구와 영어 번역. 새 UI 문구는 `AppStrings.tr`, 동적 값은 `AppStrings.format`으로 연결합니다. 번역의 `{0}` 등 자리표시자는 원문과 동일하게 유지합니다.

사용자가 작성한 이름·채팅·메모·공지 본문·일정 제목과 DB/API 상태값은 번역하지 않습니다. 이메일 및 기기 푸시 본문은 서버에서 작성하므로 이 기기 언어 설정으로 변경되지 않습니다. 서버에서 생성한 알림 목록 제목은 등록된 시스템 문구에 한해 화면에서 번역합니다.

언어 선택·저장·실패 복구, 한국어 복귀, 영어 달력·로그인 화면은 `test/locale_settings_test.dart`에서 검증합니다.
