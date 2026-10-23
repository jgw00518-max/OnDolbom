"""Firebase 인증 확인 후 MySQL 가족 사용자 조회·최초 등록."""

import re
from uuid import uuid4

from fastapi import APIRouter, Depends, HTTPException
from pydantic import BaseModel, ConfigDict, field_validator
from pymysql import MySQLError, IntegrityError

from python.database import connect
from python.features.auth.firebase_auth import require_firebase_user

router = APIRouter()


class UserProfile(BaseModel):
    user_id: str
    user_email: str | None
    name: str | None
    phone: str | None


class CurrentUserResponse(BaseModel):
    registered: bool
    user: UserProfile | None


class ProfileRegistration(BaseModel):
    model_config = ConfigDict(extra="forbid")
    name: str
    phone: str

    @field_validator("name")
    @classmethod
    def validate_name(cls, value: str) -> str:
        value = value.strip()
        if not 1 <= len(value) <= 20:
            raise ValueError("이름은 1~20자로 입력해 주세요.")
        return value

    @field_validator("phone")
    @classmethod
    def validate_phone(cls, value: str) -> str:
        value = value.strip()
        if not re.fullmatch(r"010(?:[0-9]{8}|-[0-9]{4}-[0-9]{4})", value):
            raise ValueError("전화번호는 01012345678 또는 010-1234-5678 형식으로 입력해 주세요.")
        digits = value.replace("-", "")
        return f"{digits[:3]}-{digits[3:7]}-{digits[7:]}"


def _find_profile(cursor, uid: str):
    cursor.execute(
        """SELECT user_id, user_email, name, phone, withdrawn_at
           FROM `user`
           WHERE user_firebase_uid = %s AND BINARY user_firebase_uid = BINARY %s
           LIMIT 1""", (uid, uid),
    )
    return cursor.fetchone()


def _registered_response(row):
    if row["withdrawn_at"] is not None:
        raise HTTPException(403, "탈퇴 처리된 계정입니다.")
    return CurrentUserResponse(registered=True, user=UserProfile(**row))


@router.post("/profile", response_model=CurrentUserResponse)
def register_profile(payload: ProfileRegistration, claims: dict = Depends(require_firebase_user)):
    """검증 UID에 최초 한 번만 등록한다. 재요청은 기존 프로필을 반환한다."""
    connection = None
    try:
        connection = connect()
        with connection.cursor() as cursor:
            existing = _find_profile(cursor, claims["uid"])
            if existing is not None:
                return _registered_response(existing)
            email = claims.get("email")
            if not isinstance(email, str) or not email or len(email) > 200:
                raise HTTPException(422, "로그인 계정의 이메일을 확인해 주세요.")
            cursor.execute(
                """INSERT INTO `user`
                   (user_id, user_firebase_uid, user_email, name, phone)
                   VALUES (%s, %s, %s, %s, %s)""",
                (str(uuid4()), claims["uid"], email, payload.name, payload.phone),
            )
            row = _find_profile(cursor, claims["uid"])
        if row is None:
            raise RuntimeError("Inserted profile not found")
        response = _registered_response(row)
        connection.commit()
        return response
    except IntegrityError as error:
        if connection is not None:
            connection.rollback()
        if error.args and error.args[0] == 1062:
            # 동시 요청의 UNIQUE 충돌은 새 트랜잭션에서 같은 UID인지 재확인한다.
            try:
                with connection.cursor() as cursor:
                    row = _find_profile(cursor, claims["uid"])
                if row is not None:
                    return _registered_response(row)
            except MySQLError:
                raise HTTPException(503, "사용자 정보를 다시 확인하지 못했습니다.") from None
            raise HTTPException(409, "계정 연결 정보가 충돌합니다. 기존 계정을 확인해 주세요.") from None
        raise HTTPException(503, "사용자 정보를 저장하지 못했습니다.") from None
    except HTTPException:
        if connection is not None:
            connection.rollback()
        raise
    except (MySQLError, ValueError, RuntimeError):
        if connection is not None:
            connection.rollback()
        raise HTTPException(503, "사용자 정보를 저장하지 못했습니다. 다시 시도해 주세요.") from None
    finally:
        if connection is not None:
            connection.close()


@router.get("/me", response_model=CurrentUserResponse)
def get_current_user(claims: dict = Depends(require_firebase_user)):
    connection = None
    try:
        connection = connect()
        with connection.cursor() as cursor:
            # 현재 UID 컬럼의 collation은 대소문자를 구분하지 않으므로 정확 비교도 적용한다.
            cursor.execute(
                """SELECT user_id, user_email, name, phone, withdrawn_at
                   FROM `user`
                   WHERE user_firebase_uid = %s AND BINARY user_firebase_uid = BINARY %s
                   LIMIT 1""",
                (claims["uid"], claims["uid"]),
            )
            row = cursor.fetchone()
        if row is None:
            return CurrentUserResponse(registered=False, user=None)
        if row["withdrawn_at"] is not None:
            raise HTTPException(403, "탈퇴 처리된 계정입니다.")
        return CurrentUserResponse(registered=True, user=UserProfile(**row))
    except (MySQLError, ValueError):
        raise HTTPException(503, "사용자 정보를 조회하지 못했습니다. 서버 DB 설정과 연결을 확인해 주세요.") from None
    finally:
        if connection is not None:
            connection.close()
