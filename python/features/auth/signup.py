"""이메일 소유 확인을 마친 요청만 Firebase 이메일 계정을 생성한다."""

import hmac
import time

from fastapi import APIRouter, HTTPException, Request, Response
from firebase_admin import auth
from pydantic import Field, SecretStr

from python.features.auth import password_reset as codes

router = APIRouter(prefix="/signup")


class VerifiedSignup(codes.ResetInput):
    # 외부 계약은 가입용 verification_token이다. 재설정 토큰은 받지 않는다.
    reset_token: SecretStr = Field(alias="verification_token")


@router.post("/request")
def request_code(payload: codes.EmailInput, request: Request, response: Response):
    return codes.request_email_code(payload, request, response, purpose="signup")


@router.post("/verify")
def verify_code(payload: codes.CodeInput, response: Response):
    return codes.verify_email_code(payload, response, purpose="signup")


@router.post("/confirm")
def signup(payload: VerifiedSignup, response: Response):
    response.headers["Cache-Control"] = "no-store"
    try:
        config, app, db, doc = codes.context(payload.email, "signup")

        def consume(tx):
            row = doc.get(transaction=tx).to_dict() or {}
            if (row.get("request_id") != payload.request_id or row.get("phase") != "verified"
                    or not row.get("eligible") or row.get("expires", 0) <= time.time()
                    or not hmac.compare_digest(row.get("token_hash", ""),
                        codes.digest(config["PASSWORD_RESET_SECRET"], payload.reset_token.get_secret_value()))):
                return False
            # 동시 가입에서도 한 요청만 증명을 사용한다. 실패 시 처음부터 인증한다.
            tx.update(doc, {"phase": "consumed", "token_hash": ""})
            return True

        if not codes.run_transaction(db, consume):
            raise HTTPException(400, codes.INVALID)
        # 이미 존재하는 계정을 수정하거나 소셜 계정에 비밀번호를 추가하지 않는다.
        auth.create_user(email=payload.email, password=payload.password.get_secret_value(),
                         email_verified=True, app=app)
        return {"created": True}
    except auth.EmailAlreadyExistsError:
        raise HTTPException(409, "이미 가입된 이메일입니다. 기존 가입 방식으로 로그인해 주세요.") from None
    except HTTPException:
        raise
    except Exception:
        raise HTTPException(503, "가입 결과를 확인하지 못했습니다. 로그인 확인 후 필요하면 이메일 인증을 다시 진행해 주세요.") from None
