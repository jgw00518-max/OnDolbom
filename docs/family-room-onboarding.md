# 돌봄 공간 첫 이용 안내

## 표시와 완료 기준

- 로그인·사용자 정보 등록 후 돌봄 공간 목록에 처음 진입하면 안내한다.
- 기본 동작은 **기기 설치 기준 최초 1회**다. 개발 중 로그인마다 반복하던 설정은 껐다.
- 건너뛰기·마지막 시작하기·시스템 뒤로가기로 종료하면 SharedPreferencesAsync의 `family_room.onboarding.completed`에 완료를 저장한다.
- 완료 후 목록 재진입·로그아웃·재로그인·앱 재실행 때 다시 표시하지 않는다. 완료 기록은 계정별이 아닌 기기별이며 로그아웃 때 삭제하지 않는다.
- 개발 검수 중 이미 완료했다면 그 기록을 그대로 사용한다. 다시 검수하려면 개발용 기기의 해당 키만 초기화하거나 테스트에서 반복 표시 설정을 명시적으로 켠다.
- 읽기 실패 시 기존 앱 진입을 막지 않는다. 완료 저장 실패 시 같은 앱 실행에서는 반복 표시하지 않지만 재실행 뒤에는 다시 나올 수 있다.
- 로그인 상태가 바뀌면 이전 화면의 안내를 닫고, 진행 중인 이전 확인 결과는 적용하지 않는다.

## 안내 내용과 조작

1. 하단 + 버튼으로 새 돌봄 공간 만들기
2. 원하는 가족의 공간 카드로 입장하기
3. 왼쪽 위 메뉴 버튼
4. 초대·알림·공지사항·문의·개인 설정
5. 투약일지
6. 실시간 채팅
7. 메모
8. 일정
9. 대상자 정보
10. 공간 설정

PageView와 PageController로 좌우 스와이프·다음·인디케이터를 연결한다. 하단 왼쪽은 건너뛰기, 오른쪽은 다음이며 마지막 페이지에는 시작하기를 표시한다. 종료하면 아래의 실제 공간 목록을 보여주며 임의로 공간을 선택하지 않는다.

## 화면 구성

- 원본 390:844 비율의 앱 스크린샷 전체를 축소해 중앙에 배치한다. 가로·세로를 따로 늘리거나 사진을 잘라내지 않는다.
- 주변에는 앱 테마의 peachSoft 배경과 둥근 모서리·옅은 그림자를 사용한다.
- 사진 안의 설명 대상만 밝게 남기고 나머지는 어둡게 한다. 화살표와 별도 강조 테두리는 없다.
- 강조 창의 모서리는 실제 앱 박스의 반경과 같은 비율로 축소한다. 새 공간 버튼 18, 공간 카드·돌봄 메뉴 20, 공통 메뉴 그룹 13을 사용한다.
- 메뉴 버튼은 가장자리에서 가로 8·세로 10만큼 안쪽으로 줄인 영역에 반경 18을 적용해 사진 가장자리에 닿지 않게 한다. 단위는 촬영 원본의 논리 픽셀이다.
- 설명은 강조 영역 위·아래 중 공간이 넓은 쪽에 배치하고, 큰 글씨나 짧은 화면에서는 설명 영역만 스크롤한다.
- 개발 중 핫 리로드 이전의 모서리 값이 없는 데이터도 처리하며, 핫 리로드 시 안내 데이터를 다시 읽는다.

## 스크린샷과 갱신 방법

`assets/images/onboarding/rooms.png`, `drawer.png`, `home.png`는 실제 FamilyRoomList·AccountDrawer·FamilyRoomHome 위젯을 Flutter 렌더러로 촬영한 화면이다. 예시 가족 데이터만 격리된 ProviderContainer에 제공하며 실제 계정·DB·가족 공간을 만들거나 변경하지 않는다.

이미지는 밝은 모드·한국어 기준이다. Pretendard와 MaterialIcons를 로드하고, 테스트 엔진의 기본 사각 글꼴은 실제 앱 글꼴로 대체한다. 실제 메뉴 위젯 코드는 바꾸지 않는다. `targets.json`에는 촬영 화면에서 측정한 강조 위치를 비율로 기록한다.

화면 디자인이 바뀌면 프로젝트 루트에서 다음 명령으로 이미지와 좌표를 함께 갱신한다.

```powershell
flutter test --dart-define=CAPTURE_ONBOARDING=true test/capture_family_room_onboarding_test.dart
```

일반 테스트 실행에서는 캡처를 건너뛰므로 이미지를 덮어쓰지 않는다. 갱신 뒤 이미지 세 장과 좌표 파일을 함께 검토한다.

## 파일 구성

- `lib/view/family_room/family_room_list.dart`: 최초 표시 연결
- `lib/view/family_room/family_room_onboarding.dart`: 안내 화면·강조 효과·페이지 이동
- `lib/vm/family_room/family_room_onboarding_vm.dart`: 중복 표시 방지·완료 처리
- `lib/model/family/family_room_onboarding_preferences.dart`: 로컬 완료 저장
- `lib/model/family/family_room_onboarding_step.dart`: 제목·설명·줄바꿈·강조 반경
- `assets/images/onboarding/`: 실제 화면 이미지·강조 좌표
- `test/family_room_onboarding_test.dart`: 최초 표시·완료·재로그인·화면 비율·다시 읽기 검사
- `test/capture_family_room_onboarding_test.dart`: 스크린샷 갱신 도구

추가 패키지·서버 API·DB 변경은 없다. 기존 로그인·화면 이동·실제 공간 선택 기능을 유지한다.

## 검증 방법

```powershell
flutter test test/family_room_onboarding_test.dart
flutter analyze
```

자동 검사와 실제 기기 검수를 구분한다. 실제 기기에서는 완료 기록이 없는 상태로 첫 로그인 → 돌봄 공간 진입 → 안내 종료 → 재로그인·재실행 후 미표시를 확인한다. 신규 이미지가 포함되므로 실행 중인 앱은 완전히 재시작한 뒤 확인한다.
