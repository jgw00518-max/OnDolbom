# 팀원별 로컬 실행 설정

## 개발 환경 원칙

**MySQL은 팀이 같은 서버·데이터베이스를 사용하고, FastAPI는 각자 PC에서 실행한다.**
Firebase 프로젝트와 카카오·네이버 개발자 앱도 같은 온돌봄 프로젝트를 사용한다.
팀원마다 새 Firebase 프로젝트나 새 소셜 앱을 만들면 동일 사용자의 식별자가 달라질 수 있다.
로그인/프로필/공간·초대·일정을 테스트하면 공유 데이터에 실제로 반영되므로 테스트 계정과 공간을 구분한다.
초기화 SQL, 테이블 삭제, 다른 팀원의 테스트 데이터 삭제를 실행하지 않는다.
이번 소셜 로그인 추가에는 새 MySQL 테이블이나 마이그레이션이 없다.

## 1. 의존성 설치

프로젝트 루트에서 실행한다. 처음 받은 코드는 `flutter pub get`만으로 실행 환경이 완성되지 않는다.

```powershell
flutter pub get
python -m pip install -r python/requirements.txt
```

Python 가상환경을 쓰는 경우 VS Code에서 해당 인터프리터를 선택하고 같은 환경에 설치한다.

## 2. 각자 서버의 python/.env

`python/.env.example`을 복사하고 실제 값은 팀의 안전한 공유 채널에서 전달받는다.
이미 `.env`가 있으면 덮어쓰지 말고 빠진 항목만 추가한다. `.env`는 Git에 올리지 않는다.

| 항목 | 팀원 설정 |
| --- | --- |
| MYSQL_HOST·MYSQL_PORT·MYSQL_DATABASE | 기존 공유 MySQL 서버와 DB 그대로 사용. 각자 PC의 localhost로 바꾸지 않는다 |
| MYSQL_USER·MYSQL_PASSWORD | 공유 DB 담당자가 허용한 개발용 접속 계정 |
| FIREBASE_PROJECT_ID | 같은 `ondolbom-3125e` 프로젝트 |
| GOOGLE_APPLICATION_CREDENTIALS | 각 PC에 보관한 서버용 서비스 계정 JSON의 절대 경로 |
| KAKAO_APP_ID | 같은 온돌봄 앱 ID `1622719` |
| NAVER_CLIENT_ID·NAVER_CLIENT_SECRET | 같은 온돌봄 네이버 앱에서 발급한 서버 설정 |
| NAVER_REDIRECT_URI | 에뮬레이터 기준 `http://10.0.2.2:8000/auth/naver/callback` |

Firebase Admin 키는 프로젝트 밖에 보관한다. 다른 PC의 파일 경로를 그대로 복사하면 안 된다.
`android/app/google-services.json`과 서버 Admin 키는 다른 파일이다.
공유 MySQL은 각 팀원 PC에서 접속 가능하도록 DB 서버의 네트워크·접속 권한이 준비되어 있어야 한다.
서버가 다르더라도 같은 Firebase UID로 로그인하면 공유 DB의 같은 사용자 행을 이용한다.

## 3. 앱 실행용 로컬 JSON

`config/social-login.example.json`을 `config/social-login.local.json`으로 복사한다.
이 파일도 Git 제외 대상이며 아래 내용만 각자 설정한다.

```json
{
  "KAKAO_NATIVE_APP_KEY": "팀의 동일한 카카오 Native 앱 키",
  "API_BASE_URL": "http://10.0.2.2:8000"
}
```

- Android 에뮬레이터의 `10.0.2.2`는 **그 에뮬레이터가 실행되는 PC**다.
- 그래서 모든 팀원이 같은 문자열을 써도 각자 로컬 FastAPI에 접속한다.
- API_BASE_URL에 공유 MySQL IP를 넣지 않는다. MySQL 서버 주소와 FastAPI 서버 주소는 다르다.
- Google 키·네이버 Client Secret·Firebase Admin 키는 이 파일에 넣지 않는다.
- Native 앱 키는 앱 빌드에 포함되는 클라이언트용 설정이며 서버 비밀키를 대체하지 않는다.

## 4. Google: 각 PC의 개발 인증서 등록

각 팀원의 PC마다 디버그 인증서가 다르므로 아래 지문을 담당자에게 전달해 동일 Firebase Android 앱에 추가한다.

```powershell
& 'C:\Program Files\Android\Android Studio\jbr\bin\keytool.exe' -list -v -alias androiddebugkey -keystore "$env:USERPROFILE\.android\debug.keystore" -storepass android
```

- SHA-1·SHA-256을 Firebase 프로젝트 설정 → Android 앱에 추가한다.
- Google 제공업체는 Firebase Authentication에서 활성화한다.
- 설정 후 최신 `google-services.json`을 받아 `android/app/google-services.json`에 둔다.
- 패키지는 `com.example.ondolbom`으로 일치해야 한다.
- 위 비밀번호는 기본 디버그 키의 공개된 기본값이다. 배포용 키는 별도다.

## 5. 카카오: 각 PC의 키 해시 등록

SHA-1 표시 문자열과 카카오 키 해시는 다르다. 각 PC에서 다음 PowerShell로 출력한다.

```powershell
$keytoolPath = 'C:\Program Files\Android\Android Studio\jbr\bin\keytool.exe'
$debugKeyPath = Join-Path $env:USERPROFILE '.android\debug.keystore'
$certificatePath = Join-Path $env:TEMP 'ondolbom-debug-cert.der'
& $keytoolPath -exportcert -alias androiddebugkey -keystore $debugKeyPath -storepass android -file $certificatePath
$certificateBytes = [System.IO.File]::ReadAllBytes($certificatePath)
$sha1Hasher = [System.Security.Cryptography.SHA1]::Create()
try { [Convert]::ToBase64String($sha1Hasher.ComputeHash($certificateBytes)) }
finally { $sha1Hasher.Dispose() }
```

출력값을 같은 카카오 앱의 Native 앱 키 → Android 플랫폼 키 해시에 추가한다.
현재 PC에서 받은 해시를 다른 팀원 PC에도 그대로 적용하면 안 된다.
카카오 로그인 활성화·이메일 필수 동의는 개발자 앱에서 한 번 설정한다.
Gradle이 Dart 실행 옵션으로 복귀 URL을 구성하므로 Native 키를 AndroidManifest에 직접 다시 입력하지 않는다.
현재 카카오 로그인은 카카오톡 앱 대신 브라우저의 카카오계정 인증 화면을 사용한다.

## 6. 네이버: 서버 Callback URL 등록

**이번 구현은 Client Secret을 APK에 넣지 않는 브라우저 인가 코드 방식이다.**
기존에 Android 환경만 등록했다면 동일 네이버 애플리케이션의 API 설정에 **PC 웹 환경을 추가**한다.

| 콘솔 항목 | Android 에뮬레이터용 값 |
| --- | --- |
| 서비스 URL | `http://10.0.2.2:8000` |
| Callback URL | `http://10.0.2.2:8000/auth/naver/callback` |
| 제공 정보 | 연락처 이메일 주소 필수 |

콘솔에 등록한 Callback URL, 서버 `.env`의 NAVER_REDIRECT_URI는 정확히 같아야 한다.
클라이언트 앱의 복귀 스킴 `ondolbomnaver://oauth`는 코드에 포함돼 있다.
이 스킴을 네이버의 서버 Callback URL 대신 등록하지 않는다.
Client ID·Secret은 각 로컬 서버 `.env`에만 둔다. 앱용 JSON에 넣지 않는다.
개발 중에는 네이버 콘솔의 멤버 관리에 실제 테스트에 사용할 계정을 등록한다.
일반 사용자 공개 전에는 네이버가 요구하는 검수·서비스 설정을 완료해야 한다.

네이버의 이메일은 `@naver.com` 주소가 아니라 계정의 연락처 이메일이다.
계정 식별에는 앱별 고유 ID를 사용한다. 이메일만 같다고 기존 계정과 자동 합치지 않는다.
카카오·Google·이메일 가입과 이메일이 충돌하면 기존 가입 방식으로 로그인하라는 안내가 나온다.
네이버 연락처 이메일의 제공만으로 Firebase 이메일 인증 완료로 표시하지 않는다.

로그인 요청은 5분 유효하며 해당 로컬 서버 메모리에 임시 보관한다.
서버 재시작·reload·다른 PC 서버로 접속하면 진행 중 로그인은 처음부터 다시 해야 한다.
로컬에서는 **단일 워커**로 실행한다. 배포 시 다중 워커/인스턴스를 사용하려면 공유 임시 저장소가 필요하다.

## 7. 실행

첫 번째 터미널(로그인 Callback의 인가 코드가 접근 로그에 남지 않도록 옵션 추가):

```powershell
python -m uvicorn python.main:app --host 0.0.0.0 --port 8000 --reload --no-access-log
```

두 번째 터미널:

```powershell
flutter run --dart-define-from-file=config/social-login.local.json
```

새 플러그인·Native 키·Callback 스킴을 변경한 뒤에는 Hot Reload만 하지 말고 앱을 완전히 중지 후 빌드한다.
API 문서는 PC 브라우저에서 `http://127.0.0.1:8000/docs`로 확인한다.

## 8. 실기기에서 테스트할 때

PC와 기기를 같은 네트워크에 연결하고, API_BASE_URL을 **자기 PC의 LAN IP:8000**으로 바꾼다.
PC 방화벽에서 필요한 개발용 연결을 허용한다. 주소 예시는 실제 PC IP로 대체한다.
네이버 NAVER_REDIRECT_URI도 같은 PC IP로 바꾸고 그 URL을 네이버 콘솔의 허용 Callback에 추가한다.
기기 브라우저가 서버 Callback을 열어야 하므로 PC에서만 통하는 localhost를 쓰면 안 된다.
실기기 설정은 콘솔의 URL 등록 가능 개수·조건에 맞춰 팀과 조율한다.
배포할 때는 사설 IP나 HTTP가 아닌 공용 HTTPS 서버와 배포 인증서를 사용한다.

## 9. 검증·문제 해결

| 현상 | 확인할 부분 |
| --- | --- |
| 서버 연결 실패 | 자기 PC 서버 실행, API_BASE_URL, 방화벽 |
| MySQL 연결 실패 | 공유 DB 서버 상태·권한, 서버 `.env` |
| Google 설정 오류 | 해당 PC SHA 지문, 최신 google-services.json |
| 카카오 키 입력 안내 | 일반 F5 대신 dart-define 파일을 지정해 실행했는지 |
| 카카오 인증 실패 | 해당 PC 키 해시, Native 키, 앱 ID·이메일 동의 |
| 네이버 서비스/Callback 오류 | PC 웹 환경 등록, 콘솔·.env의 URL 정확 일치 |
| 네이버 400/401 | 서버 재시작 여부, 5분 만료, 서로 다른 서버로 복귀했는지. 앱에서 다시 로그인 |
| 네이버 409 | 같은 이메일의 기존 계정 또는 연락처 이메일 변경. 자동 병합하지 않음 |
| 네이버 503 | 각 서버의 NAVER_CLIENT_ID·SECRET·REDIRECT_URI 및 인터넷 연결 |
| 최초 소셜 로그인 후 정보 입력 | 정상. 이름·전화번호 등록 후 공유 DB에 가족 프로필 생성 |

테스트 순서: 이메일 로그인 → 아이디 저장 → 자동 로그인 → Google → 카카오 → 네이버 → 계정별 공간 분리.
소셜 로그인 취소 후 버튼 복구, 최초 가입 후 재로그인 시 사용자 중복 없음도 확인한다.
자동 테스트는 제공자·Firebase 대체 객체로 수행하므로 각 PC의 실제 로그인 검증이 필요하다.

## 참고

비밀번호 재설정 메일은 각 PC의 `.env`에 SMTP 설정이 필요하다. `PASSWORD_RESET_SECRET`은 팀 전체가 같은 난수값을 사용한다. 공유 MySQL 스키마 변경은 없다. 자세한 항목과 Firestore 규칙은 아래 안내를 따른다.

- [비밀번호 재설정 설정·검증 안내](account-recovery.md)

- [소셜 로그인 구현 상세](social-login-setup.md)
- [Firebase Flutter 소셜 인증](https://firebase.google.com/docs/auth/flutter/federated-auth)
- [카카오 Flutter 설정](https://developers.kakao.com/docs/ko/flutter/getting-started)
- [네이버 로그인 API](https://developers.naver.com/docs/login/api/api.md)
- [네이버 앱 등록](https://developers.naver.com/docs/common/openapiguide/appregister.md)
