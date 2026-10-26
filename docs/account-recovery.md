# 이메일 인증번호로 비밀번호 재설정

흐름: 비밀번호 찾기 → 이메일 입력 → 인증번호 전송 → 이메일에서 번호 확인 → 앱에서 번호 입력 → 새 비밀번호와 확인 입력 → 로그인.
아이디 찾기·휴대폰 인증은 제공하지 않는다. Firebase 기본 재설정 링크 대신 서버가 인증번호 메일을 발송한다.

## 각 팀원 로컬 설정

공유 MySQL은 변경하지 않는다. 기존 Firebase 프로젝트의 Firestore를 임시 인증 상태에 사용하며, 각 PC의 FastAPI 서버가 SMTP로 메일을 보낸다.
`python/.env.example`의 다음 항목을 각자 `python/.env`에 넣는다. 실제 값은 GitHub나 채팅에 올리지 않는다.

```dotenv
PASSWORD_RESET_SECRET=팀이_공유하는_32자_이상_난수
SMTP_HOST=메일서비스의_SMTP_서버
SMTP_PORT=587
SMTP_SECURITY=starttls
SMTP_USER=발송계정
SMTP_PASSWORD=SMTP전용_비밀번호_또는_앱비밀번호
SMTP_FROM=발송이_허용된_이메일주소
```

1. 팀의 발신용 이메일/메일 서비스를 정하고 SMTP 사용 권한을 준비한다. 일반 로그인 비밀번호 대신 서비스에서 발급한 SMTP 자격증명을 사용한다.
2. 서비스 안내에 맞춰 호스트·포트·보안 방식을 입력한다. 587은 보통 `starttls`, 465는 `ssl`이다. TLS 없는 발송은 허용하지 않는다.
3. 다음 명령으로 난수를 한 번 생성하고 팀원에게 안전하게 공유한다. 모든 서버에서 같은 `PASSWORD_RESET_SECRET`을 사용한다. 각자 다르게 만들면 공통 제한이 분리되고 다른 서버에서 인증을 이어갈 수 없다.

   ```powershell
   python -c "import secrets; print(secrets.token_urlsafe(48))"
   ```

4. 기존 Firebase Admin 키와 `FIREBASE_PROJECT_ID`를 그대로 사용한다. Firestore 접근 권한이 필요하다.
5. Firebase 콘솔 Firestore 규칙에 `firestore.rules`의 두 `password_reset_*` 경로 차단 규칙을 병합한다. 기존에 전체 경로를 허용하는 규칙이 있다면 제거/제한한다. 겹치는 allow 규칙은 다른 deny 규칙으로 취소되지 않는다. 앱은 이 컬렉션을 직접 읽지 않는다.
6. 서버를 재시작하고 앱을 실행한다.

   ```powershell
   python -m uvicorn python.main:app --host 0.0.0.0 --port 8000 --reload --no-access-log
   flutter run --dart-define-from-file=config/social-login.local.json
   ```

설정이 비어 있으면 503을 반환하며 메일이 전송된 것처럼 처리하지 않는다. SMTP 테스트 메일이나 실제 비밀번호 변경은 자동 테스트에서 수행하지 않는다.
실서비스는 HTTPS 서버를 사용한다. 앱/프록시/모니터링에서 요청 본문과 응답의 인증번호·재설정 토큰·비밀번호를 수집하지 않는다.

## API

모두 로그인 전 호출한다. 성공 응답은 `Cache-Control: no-store`다.

| API | 요청 | 성공 응답 |
| --- | --- | --- |
| `POST /auth/password-reset/request` | `email` | `request_id`, `expires_in: 600`, `retry_after: 60` |
| `POST /auth/password-reset/verify` | `email`, `request_id`, `code` | 일회용 `reset_token`, `expires_in: 300` |
| `POST /auth/password-reset/confirm` | `email`, `request_id`, `reset_token`, `password` | `changed: true` |

- 이메일별 60초 간격, 시간당 5회. 직접 연결 IP별 시간당 30회. 팀원들이 같은 이메일을 테스트하면 제한도 공유된다. 프록시 배포 시 신뢰 가능한 실제 IP 처리/추가 서비스 전체 제한을 별도로 구성한다.
- 6자리 코드 10분, 오입력 5회까지. 재전송은 기존 코드와 이전 재설정 토큰을 무효화한다.
- 인증 성공 후 토큰은 5분 동안 한 번만 사용한다. 코드와 토큰 원문은 Firestore에 저장하지 않고 서버 비밀값으로 HMAC한다.
- 미가입·비활성·소셜 전용 계정은 같은 요청 응답을 주지만 메일은 보내지 않는다. 소셜 전용 계정에는 새 비밀번호 로그인 수단을 추가하지 않는다.
- 인증 성공 후 Firebase Admin으로 비밀번호를 변경하고 기존 refresh token을 철회한다. MySQL의 비밀번호 컬럼에는 기록하지 않는다.
- Firestore 트랜잭션으로 단회 사용을 먼저 확정한 뒤 Firebase를 변경한다. 두 서비스에 걸친 원자적 처리는 불가능하므로 변경/응답 실패 때 토큰을 재사용하지 않는다. 새 비밀번호 로그인을 확인하고 필요하면 인증번호를 다시 요청한다.
- 앱을 종료하면 요청 정보는 사라진다. 처음부터 다시 요청한다. 단순 메일 앱 전환은 진행 상태를 유지한다.
- 임시 컬렉션은 이메일/IP의 HMAC 식별자별 한 문서를 갱신한다. 만료는 서버가 강제 검사하며 문서 자동 삭제는 현재 구성하지 않는다. 운영 시 보존 기간과 정리 정책을 추가한다.

## 실제 검증 순서

1. 이메일/비밀번호로 가입한 테스트 계정으로 인증번호를 요청한다. 수신함·스팸함을 확인한다.
2. 잘못된 코드로 다음 단계에 갈 수 없는지 확인한다. 새 코드를 요청했다면 이전 코드는 사용할 수 없다.
3. 받은 번호를 앱에 입력하고 새 비밀번호를 두 번 입력한다. 불일치 시 변경되지 않아야 한다.
4. 성공 화면에서 로그인으로 돌아간다. 이전 비밀번호는 실패하고 새 비밀번호로 로그인되는지 확인한다.
5. 코드 만료·5회 오입력·재발송 제한·변경 완료 토큰 재사용 거절을 확인한다.
6. Google·카카오·네이버 전용 계정은 해당 제공자로 계속 로그인되는지 확인한다.

참고: [Firebase Admin 사용자 비밀번호 변경](https://firebase.google.com/docs/auth/admin/manage-users), [세션 철회](https://firebase.google.com/docs/auth/admin/manage-sessions), [Firestore 트랜잭션](https://firebase.google.com/docs/firestore/manage-data/transactions).
