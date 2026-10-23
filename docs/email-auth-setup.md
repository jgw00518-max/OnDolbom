# 이메일·비밀번호 인증과 서버 사용자 조회

## 구현 범위

- Firebase 초기화 후 Riverpod `ProviderScope`로 앱 시작
- 이메일·비밀번호 가입, 로그인, 로그아웃
- `authStateChanges()`로 로그인 복원·상태 변화에 따른 화면 전환
- 입력 검증, 비밀번호 확인, 처리 중 중복 요청 차단, 한국어 오류 표시

`AppUser`는 Firebase UID·이메일만 가진 인증 모델이다. 서버 토큰 검증과 기존 MySQL 사용자
조회·최초 프로필 등록까지 구현했다. 공간 연결·소셜 로그인은 아직 미구현이다.
Firebase 가입 직후 자동 로그인되지만 온돌봄 가족 프로필 등록 완료를 뜻하지 않는다.
이메일 소유 확인 메일을 요구하는 별도 절차는 추가하지 않았다.

## 파일과 흐름

```text
main.dart: Firebase 초기화 → ProviderScope → MyApp
authUserProvider: Firebase 인증 상태 → 비로그인 LoginView / 로그인 Home
LoginView: 로그인·가입 모드, 입력 검증
AuthVm: Firebase 이메일 인증 호출, 처리 상태·오류 관리
Home: 현재 이메일 표시·서버 사용자 조회 결과·미등록 프로필 입력·재시도·로그아웃
userProfileProvider: ID 토큰 → GET /auth/me → UserProfile 또는 미등록 상태
ProfileRegistrationVm: 이름·전화번호 → POST /auth/profile → 사용자 정보 재조회
```

가입 화면은 `login_view.dart`에서 모드를 전환하여 같은 입력 UI를 공유한다.
비밀번호는 DB·로컬 저장소·로그에 저장하지 않는다. 이메일만 앞뒤 공백을 제거하고
비밀번호는 사용자가 입력한 원문을 Firebase에 전달한다.

## 기기 확인 순서

1. Firebase Authentication에서 이메일/비밀번호 제공업체 활성화 확인.
2. `flutter run`으로 설정된 Android 또는 iOS 기기에서 실행.
   현재 생성 설정에는 Web·Windows·macOS·Linux 설정이 없으므로 해당 플랫폼에서는 초기화 오류가 표시된다.
3. 이메일 회원가입으로 테스트용 본인 이메일·비밀번호·동일한 확인 비밀번호 입력.
4. Firebase 콘솔 사용자 목록과 앱의 로그인 후 이메일 표시 확인.
5. 앱을 완전히 종료한 뒤 다시 열어 로그인 유지 확인.
6. 로그아웃 후 로그인 화면 복귀, 동일 계정 재로그인 확인.
7. 중복 이메일·틀린 비밀번호·네트워크 끊김의 오류 표시 확인.

실제 계정 생성은 기기에서 사용자가 실행한다. 자동 테스트는 가짜 Firebase 호출로
입력·VM·화면 전환을 확인하며 실제 인증 성공이나 네이티브 빌드를 증명하지 않는다.

## 서버 Firebase 설정

Firebase Console → 프로젝트 설정 → 서비스 계정에서 서버용 JSON을 발급받아 저장소 밖에 보관한다.
`firebase_options.dart`와 `google-services.json`은 서버용 비공개 키가 아니다.
`python/.env`에 다음 항목을 추가한다. 실제 키 파일 내용은 Git이나 채팅에 공유하지 않는다.

```dotenv
GOOGLE_APPLICATION_CREDENTIALS=C:/프로젝트밖경로/서비스계정키.json
FIREBASE_PROJECT_ID=ondolbom-3125e
```

키는 절대 경로를 사용한다. 서버는 `.env`보다 환경변수를 우선하고 서비스 계정의 프로젝트도
일치하는지 검사한다. 설정이 없거나 잘못되면 `/auth/me`에서 503을 반환한다.
설정 후 서버를 재시작한다. `/health`는 자격증명·DB 연결을 검사하지 않는다.

```powershell
python -m pip install -r python/requirements-dev.txt
python -m uvicorn python.main:app --host 0.0.0.0 --port 8000
```

Android 에뮬레이터의 기본 API 주소는 `http://10.0.2.2:8000`이다.
실제 기기에서는 서버 PC와 같은 네트워크에 연결하고 다음처럼 서버 PC 주소를 지정한다.
기기의 localhost는 서버 PC가 아니다. 로컬 포트 접근은 PC 방화벽 설정도 확인한다.

```powershell
flutter run --dart-define=API_BASE_URL=http://서버PC주소:8000
```

로컬 HTTP 허용은 Android debug 설정에만 추가했다. 배포는 HTTPS 주소를 사용한다.
iOS 실제 기기의 로컬 HTTP는 별도 ATS 설정이 필요할 수 있으며 이번 변경에서 전역 허용하지 않았다.
Firebase 생성 설정이 있는 Android·iOS를 대상으로 하며 Web CORS 설정은 이번 범위에 포함하지 않는다.

## 서버 연결 확인

로그인 후 홈 화면에서 ID 토큰을 서버로 보내면 다음 중 하나가 표시된다.

- MySQL 미등록: 이름·전화번호 필수 입력 폼 표시. 저장 버튼을 눌러야 등록한다.
- 등록됨: 연결된 사용자 이름 또는 이메일 표시.
- 인증·DB·통신 오류: 오류 안내와 재시도 버튼. 미등록으로 취급하지 않는다.

서버는 서명·만료·프로젝트·토큰 철회·계정 비활성화 여부를 Firebase Admin SDK로 검사한다.
토큰의 UID로 `user.user_firebase_uid`를 조회한다. 클라이언트 UID·이메일로 사용자를 선택하지 않는다.
현재 DB collation이 대소문자를 구분하지 않아 조회에 BINARY 비교를 추가했다.
조회에서는 비밀번호·Firebase UID를 반환하지 않으며 `withdrawn_at`이 있으면 403을 반환한다.
401은 Flutter에서 토큰 강제 갱신 후 한 번만 재시도한다. 그 외 실패는 수동 재시도한다.

현재 테스트는 Firebase 검증·DB·HTTP 응답을 대체한 자동 테스트다. 실제 사용자 ID 토큰을
가진 기기와 서버의 종단 연결은 위 자격증명·주소 설정 후 확인한다.

## 다음 단계

미등록 상태에서 이름과 전화번호를 입력하고 가족 사용자 정보 저장을 누른다.
이름은 앞뒤 공백 제거 후 1~20자, 전화번호는 `01012345678` 또는 `010-1234-5678`을
허용하며 DB에는 `010-1234-5678`로 저장한다. 저장 후 이름이 표시되는지 확인한다.
로그아웃·재로그인해도 입력 폼이 다시 나오지 않는지 확인한다.
타임아웃 후 재저장해도 같은 UID로 중복 생성하지 않는다. 기존 프로필 수정 API는 아니다.

서버는 실제 user 테이블에 UUID·검증 UID·검증 이메일·이름·정규화 전화번호를 INSERT한다.
비밀번호는 저장하지 않는다. 테이블 변경과 자동 테스트의 실제 DB 저장은 수행하지 않는다.
다음 구현은 가족 공간 연결 또는 Google 로그인이며 담당 기능 순서에 맞춰 진행한다.

참고: https://firebase.google.com/docs/auth/flutter/password-auth
서버 검증: https://firebase.google.com/docs/auth/admin/verify-id-tokens
