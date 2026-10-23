"""사용자 API에서 재사용할 Firebase ID 토큰 검증. 키는 저장소 밖에 둔다."""

import os
from pathlib import Path
from threading import Lock

import firebase_admin
from firebase_admin import auth, credentials, exceptions
from dotenv import dotenv_values
from fastapi import Depends, HTTPException
from fastapi.security import HTTPAuthorizationCredentials, HTTPBearer

_lock = Lock()
_app_name = "ondolbom-api"
_bearer = HTTPBearer(auto_error=False)


def get_firebase_app():
    with _lock:
        try:
            return firebase_admin.get_app(_app_name)
        except ValueError:
            pass
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
            if certificate.project_id != project_id:
                raise ValueError("Firebase project mismatch")
            return firebase_admin.initialize_app(
                certificate, {"projectId": project_id}, name=_app_name
            )
        except (ValueError, OSError, TypeError):
            raise HTTPException(503, "서버 Firebase 자격증명 설정을 확인해 주세요.") from None


def verify_firebase_token(token: str) -> dict:
    app = get_firebase_app()
    try:
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
    if authorization is None:
        raise HTTPException(401, "로그인이 필요합니다.", headers={"WWW-Authenticate": "Bearer"})
    return verify_firebase_token(authorization.credentials)
