# 투약일지 프론트엔드

## 구현 범위

목업의 시간별 그룹 목록과 약 추가 입력창을 참고했습니다.
색상을 별도로 지정하지 않고 `main.dart`의 `colorScheme`, `appBarTheme`,
`cardTheme`와 Material 버튼 테마를 사용합니다. `main.dart`는 변경하지 않습니다.

- 홈의 돌봄 메뉴에서 메모 또는 투약일지로 이동
- 선택 공간과 날짜의 투약일지 조회, 날짜 이전·다음·오늘 이동과 달력 선택
- 복약 시간별 카드, 불러온 기록의 완료 개수와 복약 상태 표시
- 항목을 눌러 약 정보·날짜·시간·용량·작성자 상세 확인
- 약 추가 시 식사·식전/식후·분, 약 정보, 용량, 단위 입력
- 입력 검증, 작성 중 취소 확인, 중복 제출 방지, 저장 실패 시 입력 보존
- 저장 성공 후 해당 공간·날짜 목록 갱신, 새로고침·추가 조회·오류 재시도

홈의 진입 메뉴는 로컬 작업 파일에만 연결되어 있습니다. 사용자 요청에 따라
`lib/view/home.dart`는 이번 커밋에서 제외합니다. 커밋만 체크아웃한 환경에서는
기존 홈 또는 라우트에 `MedicationListView` 진입을 별도로 연결해야 합니다.

수정·삭제·복약 완료 체크 API는 아직 없으므로 조작 버튼은 제공하지 않습니다.
복약 상태는 서버의 `medication_confirmed_at` 값으로 표시하며, 새 기록은 미확인 상태입니다.
추가한 기록은 선택한 날짜 한 번의 기록이며 반복 일정으로 생성하지 않습니다.

## 파일

| 파일 | 역할 |
| --- | --- |
| `lib/model/medications/medication.dart` | JSON 모델, 날짜와 용량 표시·검증 |
| `lib/vm/medications/medication_vm.dart` | Riverpod 상태, 조회·작성 API와 페이지 처리 |
| `lib/view/medications/medication_list_view.dart` | 날짜·시간별 목록과 상세 |
| `lib/view/medications/medication_form_view.dart` | 약 추가 입력창 |
| `lib/vm/family_context.dart` | 두 기능이 공유하는 선택 공간·사용자·서버 주소와 인증 토큰 연결 지점 |
| `lib/view/home.dart` | 메모·투약일지 진입 메뉴 |

기존 `memoContextProvider`는 `familyContextProvider`의 별칭으로 유지합니다.
따라서 메모와 투약일지에 서로 다른 공간 상태를 복사해서 두지 않습니다.
투약일지 목록은 공간·사용자·날짜를 키로 분리하고 오래된 요청의 결과가 새 상태를 덮어쓰지 않게 합니다.

## API 계약

목록은 `GET /medications/select`에 `family_room_id`, `medication_date`, `limit=20`,
`offset`을 전달합니다. 날짜는 `YYYY-MM-DD`입니다.

작성은 `POST /medications/insert`에 다음 필드만 보냅니다.

```json
{
  "family_room_id": "공간ID",
  "medication_info": "기록할 약 정보",
  "medication_date": "2026-10-23",
  "medication_time": "아침 식후 30분",
  "dosage": "0.500",
  "dosage_unit": "정"
}
```

사용자 ID와 투약 확인 시각은 본문에 보내지 않습니다.
용량은 부동소수점 변환 없이 숫자 문자열로 전달하고 양수·정수부 7자리·소수부 3자리 이내를 검증합니다.
약 정보는 100자, 단위는 20자 이내입니다. 분은 0~9999 범위이며
식사·시점·분을 합친 문자열을 서버의 `medication_time`에 저장합니다.
입력 기본값은 목업을 따른 것이며 사용자가 실제 기록에 맞게 선택합니다.

## 실행과 인증 연결

프로젝트 루트에서 서버를 실행하고 별도 터미널에서 Flutter를 실행합니다.

```powershell
python -m python.main
```

```powershell
flutter run --dart-define=API_BASE_URL=http://10.0.2.2:8000
```

서버 주소는 로그인·가족 공간 기능과 같은 설정을 사용하며 기본값은 `http://10.0.2.2:8000`입니다.
데스크톱·웹은 `API_BASE_URL=http://127.0.0.1:8000`을 지정합니다. `API_BASE_URL` 실행 옵션으로 바꿀 수 있습니다.
실제 기기에서는 기기가 접근할 수 있는 서버 주소와 서버 바인딩 설정이 필요합니다.

가족 공간 홈의 투약일지 메뉴에서 목록으로 이동합니다.
현재 선택한 공간과 서버에서 조회한 MySQL 사용자 프로필을 사용하며, 실행 옵션의 공간·사용자 ID는 사용하지 않습니다.
`apiTokenLoaderProvider`는 현재 로그인한 사용자의 Firebase ID 토큰을 가져옵니다.
투약일지 VM은 조회·작성 요청에 `Authorization: Bearer ...` 헤더를 전달합니다.
토큰이 없으면 서버 요청을 보내지 않으며, 서버는 각 라우터에서 토큰과 공간 권한을 확인합니다.
미인증·권한 거절은 화면에 표시하며 테스트용 기록으로 대체하지 않습니다.

## 검증

```powershell
flutter analyze --no-pub
flutter test --no-pub
```

`test/medication_test.dart`에서 모델 변환·입력 검증, 실제 앱 테마,
작성 후 조회 갱신, 작은 화면과 실패 시 입력 보존, 중복 제출 방지,
인증 오류·재시도, 날짜·공간 상태 분리와 페이지 처리를 모의 API로 검증합니다.
테스트는 실제 투약 기록을 작성하지 않습니다.
테스트는 앱의 테마를 사용하되 투약일지 화면을 직접 실행하므로 제외된 홈 파일에 의존하지 않습니다.
