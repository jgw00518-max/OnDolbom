"""사용자 API에서 재사용할 Firebase ID 토큰 검증. 키는 저장소 밖에 둔다."""

import os
from pathlib import Path
from threading import Lock

import firebase_admin
from firebase_admin import auth, credentials, exceptions
from dotenv import dotenv_values
from fastapi import Depends, HTTPException
from fastapi.security import HTTPAuthorizationCredentials, HTTPBearer

# 여러 요청이 동시에 시작되어도 동일 프로세스에서 Admin 앱을 중복 초기화하지 않는다.
_lock = Lock()
_app_name = "ondolbom-api"
_bearer = HTTPBearer(auto_error=False)


def get_firebase_app():
    # 초기화된 앱은 재사용한다. 자격증명 변경 후에는 서버를 재시작해야 한다.
    with _lock:
        try:
            return firebase_admin.get_app(_app_name)
        except ValueError:
            pass
        # 앱용 firebase_options.dart와 별개로 서버 전용 서비스 계정 키를 읽는다.
        values = {**dotenv_values(Path(__file__).resolve().parents[2] / ".env"), **os.environ}
        key_path = values.get("GOOGLE_APPLICATION_CREDENTIALS")
        project_id = values.get("FIREBASE_PROJECT_ID")
        if not key_path or not project_id:
            raise HTTPException(503, "서버 Firebase 자격증명 설정이 필요합니다.")
        try:
            path = Path(key_path)
            if not path.is_absolute():
                raise ValueError("Absolute path required")
            certificate = credentials.Certificate(str(path))
            # 다른 Firebase 프로젝트의 키를 실수로 사용하지 않도록 설정과 비교한다.
            if certificate.project_id != project_id:
                raise ValueError("Firebase project mismatch")
            return firebase_admin.initialize_app(
                certificate, {"projectId": project_id}, name=_app_name
            )
        except (ValueError, OSError, TypeError):
            # 키 파일 경로나 내부 내용을 API 응답으로 노출하지 않는다.
            raise HTTPException(503, "서버 Firebase 자격증명 설정을 확인해 주세요.") from None


def verify_firebase_token(token: str) -> dict:
    app = get_firebase_app()
    try:
        # 서명·만료·프로젝트를 검증하고, 철회 토큰과 비활성화 계정도 확인한다.
        claims = auth.verify_id_token(token, app=app, check_revoked=True)
    except (auth.InvalidIdTokenError, auth.RevokedIdTokenError, auth.UserDisabledError, auth.UserNotFoundError, ValueError):
        raise HTTPException(401, "로그인 정보가 유효하지 않습니다. 다시 로그인해 주세요.",
                            headers={"WWW-Authenticate": "Bearer"}) from None
    except (auth.CertificateFetchError, exceptions.FirebaseError):
        raise HTTPException(503, "인증 서버에 연결하지 못했습니다. 잠시 후 다시 시도해 주세요.") from None
    if not isinstance(claims.get("uid"), str) or not 1 <= len(claims["uid"]) <= 128:
        raise HTTPException(401, "로그인 정보가 유효하지 않습니다.")
    return claims


def require_firebase_user(
    authorization: HTTPAuthorizationCredentials | None = Depends(_bearer),
) -> dict:
    # 각 보호 API에서 Depends로 재사용한다. 인증 실패 시 DB 작업 전에 중단한다.
    if authorization is None:
        raise HTTPException(401, "로그인이 필요합니다.", headers={"WWW-Authenticate": "Bearer"})
    return verify_firebase_token(authorization.credentials)
