"""이메일 OTP 재설정. 임시 증명은 Firestore, 실제 비밀번호는 Firebase Auth에 둔다."""

import hashlib
import hmac
import os
from pathlib import Path
import re
import secrets
import smtplib
import ssl
import time
from email.message import EmailMessage
from email.utils import formataddr, parseaddr

from dotenv import dotenv_values
from fastapi import APIRouter, HTTPException, Request, Response
from firebase_admin import auth, firestore
from pydantic import BaseModel, ConfigDict, SecretStr, field_validator

from python.features.auth.firebase_auth import get_firebase_app
from python.features.auth.email_template import verification_message

router = APIRouter(prefix="/password-reset")
INVALID = "인증 정보가 만료되었거나 일치하지 않습니다. 인증번호를 다시 요청해 주세요."


def settings():
    values = {**dotenv_values(Path(__file__).resolve().parents[2] / ".env"), **os.environ}
    required = ("PASSWORD_RESET_SECRET", "SMTP_HOST", "SMTP_USER", "SMTP_PASSWORD", "SMTP_FROM")
    if any(not values.get(key) for key in required) or len(values["PASSWORD_RESET_SECRET"]) < 32:
        raise HTTPException(503, "서버의 인증 메일 설정이 필요합니다.")
    return values


def digest(secret, value):
    # 6자리 코드의 오프라인 전수조사를 막도록 공유 서버 비밀값으로 HMAC한다.
    return hmac.new(secret.encode(), value.encode(), hashlib.sha256).hexdigest()


def send_code(config, email, code, purpose="password_reset"):
    message = EmailMessage()
    message["Subject"] = "온돌봄 회원가입 인증번호" if purpose == "signup" else "온돌봄 비밀번호 재설정 인증번호"
    # 수신함에서도 이메일 주소 대신 서비스 이름이 먼저 표시되도록 한다.
    message["From"] = formataddr(("온돌봄", parseaddr(config["SMTP_FROM"])[1]))
    message["To"] = email
    text, html = verification_message(code, purpose)
    message.set_content(text)
    message.add_alternative(html, subtype="html")
    # TLS 없는 SMTP는 허용하지 않는다. 비밀번호·코드는 로그에 남기지 않는다.
    port = int(config.get("SMTP_PORT") or 587)
    secure = config.get("SMTP_SECURITY", "starttls")
    if secure not in ("ssl", "starttls"):
        raise ValueError("Invalid SMTP security")
    factory = smtplib.SMTP_SSL if secure == "ssl" else smtplib.SMTP
    kwargs = {"context": ssl.create_default_context()} if secure == "ssl" else {}
    with factory(config["SMTP_HOST"], port, timeout=15, **kwargs) as server:
        if secure == "starttls":
            server.starttls(context=ssl.create_default_context())
        server.login(config["SMTP_USER"], config["SMTP_PASSWORD"])
        server.send_message(message)


class EmailInput(BaseModel):
    model_config = ConfigDict(extra="forbid")
    email: str

    @field_validator("email")
    @classmethod
    def email_format(cls, value):
        value = value.strip().lower()
        if len(value) > 200 or not re.fullmatch(r"[^\s@]+@[^\s@]+\.[^\s@]+", value):
            raise ValueError("이메일 형식을 확인해 주세요.")
        return value


class CodeInput(EmailInput):
    request_id: str
    code: SecretStr


class ResetInput(EmailInput):
    request_id: str
    reset_token: SecretStr
    password: SecretStr

    @field_validator("password")
    @classmethod
    def password_length(cls, value):
        if not 6 <= len(value.get_secret_value()) <= 128:
            # Pydantic 기본 오류의 input에 비밀번호가 반사되지 않도록 직접 응답한다.
            raise HTTPException(422, "비밀번호는 6~128자로 입력해 주세요.")
        return value


def password_user(email, app):
    try:
        user = auth.get_user_by_email(email, app=app)
    except auth.UserNotFoundError:
        return None
    # 소셜 전용 계정에 새 비밀번호 로그인 경로를 추가하지 않는다.
    if user.disabled or not any(p.provider_id == "password" for p in user.provider_data):
        return None
    return user


def context(email, purpose="password_reset"):
    config = settings()
    app = get_firebase_app()
    db = firestore.client(app=app)
    secret = config["PASSWORD_RESET_SECRET"]
    # 가입과 재설정의 증명은 서로 다른 컬렉션에 두어 용도 교환을 차단한다.
    doc = db.collection(f"{purpose}_challenges").document(digest(secret, "email:" + email))
    return config, app, db, doc


def run_transaction(db, operation):
    return firestore.transactional(operation)(db.transaction())


@router.post("/request")
def request_code(payload: EmailInput, request: Request, response: Response):
    return request_email_code(payload, request, response)


def request_email_code(payload, request, response, purpose="password_reset"):
    response.headers["Cache-Control"] = "no-store"
    try:
        config, app, db, doc = context(payload.email, purpose)
        secret = config["PASSWORD_RESET_SECRET"]
        now = time.time()
        request_id = secrets.token_urlsafe(32)
        code = f"{secrets.randbelow(1000000):06d}"
        # 신뢰하지 않는 X-Forwarded-For 대신 직접 연결 주소로 보조 제한을 적용한다.
        ip = request.client.host if request.client else "unknown"
        ip_doc = db.collection(f"{purpose}_limits").document(digest(secret, "ip:" + ip))

        def reserve(tx):
            previous = doc.get(transaction=tx).to_dict() or {}
            limit = ip_doc.get(transaction=tx).to_dict() or {}
            if now - previous.get("sent_at", 0) < 60:
                return False
            count = limit.get("count", 0) if now - limit.get("start", 0) < 3600 else 0
            email_count = previous.get("count", 0) if now - previous.get("start", 0) < 3600 else 0
            if count >= 30 or email_count >= 5:
                return False
            tx.set(ip_doc, {"start": limit.get("start", now) if count else now, "count": count + 1})
            tx.set(doc, {"request_id": request_id, "sent_at": now, "expires": now + 600,
                         "start": previous.get("start", now) if email_count else now,
                         "count": email_count + 1, "attempts": 0, "phase": "sending",
                         "code_hash": digest(secret, request_id + ":" + code)})
            return True

        if not run_transaction(db, reserve):
            raise HTTPException(429, "잠시 후 다시 요청해 주세요. 재발송은 60초 후 가능합니다.")
        if purpose == "signup":
            try:
                auth.get_user_by_email(payload.email, app=app)
                eligible = False
            except auth.UserNotFoundError:
                eligible = True
            user = None
        else:
            user = password_user(payload.email, app)
            eligible = user is not None
        if eligible:
            if purpose == "signup":
                send_code(config, payload.email, code, purpose="signup")
            else:
                send_code(config, payload.email, code)

        def activate(tx):
            row = doc.get(transaction=tx).to_dict() or {}
            if row.get("request_id") == request_id:
                tx.update(doc, {"phase": "code", "uid": user.uid if user else None,
                                "eligible": eligible})
        run_transaction(db, activate)
        # 미가입·소셜 전용·중지 계정 모두 같은 형태의 응답을 반환한다.
        return {"request_id": request_id, "expires_in": 600, "retry_after": 60}
    except HTTPException:
        raise
    except Exception:
        raise HTTPException(503, "인증 메일을 요청하지 못했습니다. 서버 설정을 확인해 주세요.") from None


@router.post("/verify")
def verify_code(payload: CodeInput, response: Response):
    return verify_email_code(payload, response)


def verify_email_code(payload, response, purpose="password_reset"):
    response.headers["Cache-Control"] = "no-store"
    try:
        config, _, db, doc = context(payload.email, purpose)
        token = secrets.token_urlsafe(32)
        secret = config["PASSWORD_RESET_SECRET"]

        def verify(tx):
            row = doc.get(transaction=tx).to_dict() or {}
            if (row.get("request_id") != payload.request_id or row.get("phase") != "code"
                    or row.get("expires", 0) <= time.time() or row.get("attempts", 5) >= 5):
                return False
            valid = hmac.compare_digest(row.get("code_hash", ""), digest(secret, payload.request_id + ":" + payload.code.get_secret_value()))
            eligible = row.get("eligible") if purpose == "signup" else row.get("uid")
            if not valid or not eligible:
                # 예외를 트랜잭션 안에서 던지면 실패 횟수도 롤백되므로 결과를 반환한다.
                tx.update(doc, {"attempts": row["attempts"] + 1})
                return False
            tx.update(doc, {"phase": "verified", "token_hash": digest(secret, token),
                            "expires": time.time() + 300, "code_hash": ""})
            return True
        if not run_transaction(db, verify):
            raise HTTPException(400, INVALID)
        token_field = "verification_token" if purpose == "signup" else "reset_token"
        return {token_field: token, "expires_in": 300}
    except HTTPException:
        raise
    except Exception:
        raise HTTPException(503, "인증 서버에 연결하지 못했습니다.") from None


@router.post("/confirm")
def confirm_reset(payload: ResetInput, response: Response):
    response.headers["Cache-Control"] = "no-store"
    try:
        config, app, db, doc = context(payload.email)

        def consume(tx):
            row = doc.get(transaction=tx).to_dict() or {}
            if (row.get("request_id") != payload.request_id or row.get("phase") != "verified"
                    or row.get("expires", 0) <= time.time()
                    or not hmac.compare_digest(row.get("token_hash", ""), digest(config["PASSWORD_RESET_SECRET"], payload.reset_token.get_secret_value()))):
                return None
            # 먼저 단회 사용을 확정한다. Firebase 실패 시 새 인증으로 재시도한다.
            tx.update(doc, {"phase": "consumed", "token_hash": ""})
            return row["uid"]
        uid = run_transaction(db, consume)
        if not uid:
            raise HTTPException(400, INVALID)
        user = password_user(payload.email, app)
        if user is None or user.uid != uid:
            raise HTTPException(400, INVALID)
        auth.update_user(uid, password=payload.password.get_secret_value(), app=app)
        auth.revoke_refresh_tokens(uid, app=app)
        return {"changed": True}
    except HTTPException:
        raise
    except Exception:
        # 분산 저장소 사이의 실패는 성공으로 표시하지 않는다. 이전 토큰 재사용도 금지한다.
        raise HTTPException(503, "변경 결과를 확인하지 못했습니다. 로그인 확인 후 필요하면 인증번호를 다시 요청해 주세요.") from None
