# 구현된 사용자 인증 API

## GET /auth/me

`Authorization: Bearer <Firebase ID token>`이 필요하다. 커스텀 토큰이나
소셜 서비스의 access token을 직접 전달하는 API가 아니다.

인증된 UID에 연결된 프로필을 조회하며 계정을 생성하지 않는다.

미등록 응답 (200):

```json
{"registered": false, "user": null}
```

등록 응답 (200, 값은 설명용 예시):

```json
{
  "registered": true,
  "user": {
    "user_id": "내부사용자ID",
    "user_email": "family@example.com",
    "name": "가족",
    "phone": null
  }
}
```

`user_email`, `name`, `phone`은 현재 DB에서 NULL을 허용한다.
검증된 UID는 `user.user_firebase_uid`와 정확히 비교한다.
이름·전화번호가 비어 있어도 UID 연결 행이 존재하면 registered는 true다.
프로필 필수 정보 완료 여부는 다음 등록 단계에서 별도로 처리한다.

| 코드 | 의미 |
| --- | --- |
| 401 | 토큰 없음·형식 오류·만료·유효하지 않음·철회·Firebase 계정 사용 불가 |
| 403 | MySQL 사용자 withdrawn_at 존재 |
| 503 | Firebase 자격증명·인증 서버·DB 설정 또는 연결 오류 |

오류 본문은 FastAPI 기본 `{"detail": "안내 메시지"}` 형식이다.
401은 재로그인 또는 토큰 갱신 대상이며 503을 프로필 미등록으로 해석하지 않는다.

## GET /health

인증 없이 `{"status": "ok"}`를 반환한다. 서버 프로세스만 확인한다.

## POST /auth/profile

Firebase ID 토큰 인증 후 가족 사용자 정보를 최초 등록한다.

```json
{"name": "가족", "phone": "01012345678"}
```

- 이름: 앞뒤 공백 제거 후 필수, 1~20자(현재 name 컬럼 길이).
- 전화번호: 필수. `01012345678`과 `010-1234-5678` 두 형식을 허용하며
  저장은 `010-1234-5678`로 통일한다. 현재 구현은 010 번호 기준이다.
- 클라이언트 UID·이메일·user_id 필드는 받지 않는다. 추가 필드는 422로 거절한다.
- user_id는 서버 UUID, user_firebase_uid와 user_email은 검증된 토큰에서 얻는다.
- INSERT에서 user_password는 제외하여 NULL로 둔다. 등록 시각은 DB 기본값을 사용한다.
- 성공은 200이며 GET /auth/me의 등록 응답과 같은 형식이다.
- 같은 UID의 재요청은 기존 정보를 반환하며 이름·전화번호를 수정하지 않는다.
  동시 INSERT의 UNIQUE 충돌은 rollback 후 같은 UID의 기존 행을 다시 조회한다.
- UID 대소문자 collation 충돌 등 다른 행과의 충돌은 409이며 자동 연결하지 않는다.
- 탈퇴 행은 403, 입력 오류·토큰 이메일 없음 또는 길이 초과는 422,
  저장 실패는 rollback 후 503이다. 실패 후 재요청할 수 있다.

등록 완료 후 Flutter가 GET /auth/me를 다시 조회하여 입력 폼 대신 연결된 사용자 정보를 표시한다.
DB 스키마는 변경하지 않으며 사용자 저장은 앱에서 등록 버튼을 누를 때 수행한다.
