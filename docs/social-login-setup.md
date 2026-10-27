# 소셜 로그인 연결(Android 우선)

## 현재 상태

- Google 버튼 → Google 계정 선택 → Firebase 자격증명 로그인 코드 구현.
- Firebase 세션과 기존 MySQL 프로필 등록 흐름을 재사용한다.
- 최초 계정은 기존 이름·전화번호 필수 입력 화면으로 이동한다.
- 아이디 저장·자동 로그인 옵션을 Google·카카오 로그인에도 적용한다.
- Google 취소는 오류로 표시하지 않는다. 다른 인증 방식과 충돌하면 기존 방식으로 로그인하도록 안내한다.
- 기존 계정과 이메일이 같다는 이유만으로 MySQL 사용자나 Firebase UID를 자동 병합하지 않는다.
- 실제 Google 로그인의 성공 여부는 콘솔 설정 후 기기에서 검증해야 한다.
- 카카오 계정 로그인 → 서버 토큰 검증 → Firebase Custom Token 로그인 구현. 실제 키 입력과 기기 검증은 필요하다.
- 네이버 브라우저 인증 → 서버 인가 코드 교환 → Firebase Custom Token 로그인 구현. 콘솔 PC 웹 Callback 등록 후 실제 검증이 필요하다.
- iOS·Web 소셜 로그인은 이번 단계의 검증 범위가 아니다.

## Google 설정

1. Firebase Authentication의 Google 제공업체를 활성화한다.
2. 프로젝트 설정 → 내 앱 → Android(`com.example.ondolbom`)에서 개발 PC의 SHA-1·SHA-256을 추가한다.
3. 같은 화면에서 `google-services.json`을 다시 다운로드한다.
4. `android/app/google-services.json`을 새 파일로 교체한다. Admin 서비스 계정 키와 다른 파일이다.
5. 앱을 완전히 중지하고 `flutter run`으로 다시 빌드한다.
6. Google로 계속하기 → 계정 선택 → 최초 이름·전화번호 등록 → MySQL 사용자 연결을 확인한다.
7. 로그아웃 후 재로그인, 계정 선택 취소, 자동 로그인 선택/해제, 다른 계정 선택도 확인한다.

개발 PC 인증서 지문 확인(PowerShell):

```powershell
& 'C:\Program Files\Android\Android Studio\jbr\bin\keytool.exe' -list -v -alias androiddebugkey -keystore "$env:USERPROFILE\.android\debug.keystore" -storepass android
```

위 비밀번호는 Android 기본 디버그 키의 공개된 기본값이다. 릴리스 서명 인증서는 별도 등록한다.
설정 파일에 Web OAuth 클라이언트가 없으면 Google SDK 초기화/인증에 실패할 수 있다.

## 카카오 준비

1. Kakao Developers에 온돌봄 앱을 만든다.
2. Android 플랫폼에 패키지 `com.example.ondolbom`과 실제 디버그 키 해시를 등록한다.
   카카오 키 해시는 SHA-1의 표시 문자열과 다르므로 그대로 붙여넣지 않는다.
3. 카카오 로그인을 활성화하고 계정 이메일 동의항목 사용 가능 여부를 확인한다.
4. Native 앱 키(클라이언트 SDK용), 앱 ID(서버 검증용)를 로컬 설정에 준비한다.
5. `config/social-login.local.json`의 `KAKAO_NATIVE_APP_KEY`에 Native 앱 키를 입력한다.
   이 파일은 Git 제외 대상이다. 없는 경우 example 파일을 복사한다.
6. 서버 `python/.env`에 `KAKAO_APP_ID=1622719`를 설정한다. 실제 프로젝트가 다르면 해당 앱 ID를 사용한다.
7. 서버를 재시작하고 앱을 아래 명령으로 완전히 다시 빌드한다.

```powershell
python -m uvicorn python.main:app --host 0.0.0.0 --port 8000 --reload
# 별도 터미널
flutter run --dart-define-from-file=config/social-login.local.json
```

Gradle은 같은 Dart 실행 옵션으로 Android 복귀 URL을 구성한다. Native 키를 두 파일에 중복 입력하지 않는다.
현재 흐름은 카카오톡을 자동 실행하는 대신 브라우저의 카카오계정 인증 화면을 사용한다.
토큰 검증 API는 `/auth/kakao`다. 클라이언트가 보낸 이메일·사용자 ID는 신뢰하지 않는다.
서버는 `app_id`, 만료, 회원번호 일치, 이메일 유효·인증 여부를 확인한다.
Firebase UID는 `kakao:회원번호`로 고정한다. 기존 이메일과 충돌하면 409를 반환하며 자동 병합하지 않는다.
이메일이 변경됐거나 계정이 비활성화된 경우도 Custom Token을 발급하지 않는다.
Admin 키·카카오 Admin 키·Client Secret은 Flutter 실행 설정에 넣지 않는다.
개발 중 에뮬레이터는 예시의 HTTP 주소를 사용하고 배포 서버는 반드시 HTTPS로 설정한다.

### 카카오 검증

1. 카카오로 계속하기 → 이메일 동의 → 최초 이름·전화번호 등록을 확인한다.
2. Firebase 사용자가 `kakao:` UID로 생성되고 MySQL 사용자 UID와 일치하는지 확인한다.
3. 재로그인해도 사용자·프로필이 중복되지 않는지 확인한다.
4. 취소·이메일 동의 없음·다른 앱의 토큰·기존 이메일 충돌·자동 로그인 선택/해제를 확인한다.
5. SDK/서버 자동 테스트는 실제 카카오 계정 로그인이나 서명 설정을 대신하지 않는다.

이메일 제공 거부나 권한 부족 시 별도 처리가 필요하다. 현재 프로필 API는 이메일이 필수다.

## 네이버 준비

1. NAVER Developers에서 애플리케이션을 등록하고 네이버 로그인 API를 선택한다.
2. Android 패키지 `com.example.ondolbom` 및 콘솔에서 요구하는 앱 정보를 등록한다.
3. 이메일 제공 항목과 개발 중 테스트 계정을 설정한다.
4. Client ID·Client Secret을 준비한다. 비밀값은 채팅이나 Git에 올리지 않는다.
5. 같은 앱에 PC 웹 환경을 추가하고 서비스 URL `http://10.0.2.2:8000`, Callback URL `http://10.0.2.2:8000/auth/naver/callback`을 등록한다.
6. 서버 `.env`에 NAVER_REDIRECT_URI를 같은 값으로 설정한다.
7. 서버 시작 → 앱 완전 재빌드 → 네이버로 계속하기를 검증한다.

네이버는 Firebase Google 제공업체처럼 콘솔에서 단순 활성화하는 방식이 아니다.
앱 복귀 스킴은 `ondolbomnaver://oauth`이며 Client Secret이나 Firebase 토큰을 URL로 전달하지 않는다.
앱만 가진 난수의 해시와 서버 state를 연결해 복귀 URL을 가로챈 앱의 코드 교환을 차단한다.
교환 요청은 한 번만 처리하며, 서버 재시작·reload 시 진행 중 로그인은 다시 시작해야 한다.
네이버 연락처 이메일은 별도로 검증 완료 처리하지 않는다. 기존 계정과 자동 병합하지 않는다.
자세한 팀원별 설정과 실기기 주소는 [팀원 로컬 설정](team-local-setup.md)을 참고한다.

## 공식 문서

- https://firebase.google.com/docs/auth/flutter/federated-auth
- https://pub.dev/packages/google_sign_in
- https://developers.kakao.com/docs/ko/kakaologin/flutter
- https://developers.naver.com/docs/login/devguide
