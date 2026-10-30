# 글씨 크기 설정

개인 설정 → 글씨 크기에서 **작게(90%)·보통(100%)·크게(120%)**를 선택한다. 기본값은 보통이다.

- 선택한 크기를 이 기기에 저장한다. 계정 변경·로그아웃으로 초기화하지 않는다.
- 저장 키: SharedPreferences `appearance.text_size`. 값: `small`, `medium`, `large`.
- 저장 성공 후 앱 전체와 설정 미리보기에 즉시 적용한다. 실패 시 이전 크기를 유지하고 설정 화면에 오류를 안내한다.
- 앱 재실행 시 저장한 값을 복원한다. 최초 읽기 실패 시 보통 배율로 앱을 표시하고, 설정 화면에서 다시 불러올 수 있다.
- 휴대폰의 시스템 글씨 크기를 덮어쓰지 않는다. 시스템 `TextScaler.scale(fontSize)` 결과에 앱 배율을 곱한다. 시스템의 비선형 글씨 확대도 유지한다.
- `MaterialApp.builder`에서 Navigator 바깥의 `MediaQuery`에 적용하므로 열린 화면, 새 화면, 팝업이 같은 배율을 사용한다. 위젯마다 글자 크기에 앱 배율을 다시 곱하지 않는다.
- 이미지·아이콘의 크기나 다른 앱·브라우저·내보낸 문서의 글꼴은 변경하지 않는다.

파일:

- `lib/model/settings/text_size_preferences.dart`: 옵션과 기기 저장소.
- `lib/vm/settings/text_size_vm.dart`: 읽기·저장·중복 요청 및 오류 처리.
- `lib/view/widgets/app_text_scale.dart`: 시스템 배율과 앱 배율 결합.
- `lib/view/auth/personal_settings_view.dart`: 선택 UI.

확인: 글씨 크기를 선택한 뒤 다른 화면과 팝업을 확인하고, 앱을 완전히 종료한 다음 다시 실행해 선택이 유지되는지 확인한다. 휴대폰 글씨 크기도 키워 두 설정이 함께 반영되는지 확인한다.
