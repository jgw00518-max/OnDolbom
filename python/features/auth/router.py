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
    # 외부 응답 필드만 정의한다. 비밀번호·Firebase UID는 반환하지 않는다.
    user_id: str
    user_email: str | None
    name: str | None
    phone: str | None


class CurrentUserResponse(BaseModel):
    # 등록된 행의 존재 여부다. 공간 참여 여부나 모든 프로필 필드의 완성을 뜻하지 않는다.
    registered: bool
    user: UserProfile | None


class ProfileRegistration(BaseModel):
    # 클라이언트가 user_id·UID·이메일을 주입하지 못하게 허용 필드를 제한한다.
    model_config = ConfigDict(extra="forbid")
    name: str
    phone: str

    @field_validator("name")
    @classmethod
    def validate_name(cls, value: str) -> str:
        # 실제 user.name의 VARCHAR(20) 길이와 필수 입력 조건에 맞춘다.
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
        # 입력 형식과 관계없이 DB에는 010-1234-5678 형태만 저장한다.
        digits = value.replace("-", "")
        return f"{digits[:3]}-{digits[3:7]}-{digits[7:]}"


def _find_profile(cursor, uid: str):
    # 현재 DB collation은 대소문자를 구분하지 않아 BINARY로 UID 정확 비교를 보강한다.
    cursor.execute(
        """SELECT user_id, user_email, name, phone, withdrawn_at
           FROM `user`
           WHERE user_firebase_uid = %s AND BINARY user_firebase_uid = BINARY %s
           LIMIT 1""", (uid, uid),
    )
    return cursor.fetchone()


def _registered_response(row):
    # 이미 저장된 탈퇴 사용자에게 재등록이나 정상 로그인 응답을 허용하지 않는다.
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
            # 응답 유실 후 재요청해도 기존 행을 반환하며 이름·전화번호를 덮어쓰지 않는다.
            existing = _find_profile(cursor, claims["uid"])
            if existing is not None:
                return _registered_response(existing)
            # 앱을 우회해 Firebase에서 직접 가입해도 미인증 이메일로 새 가족 프로필을 만들 수 없다.
            # 기존 등록 사용자의 로그인과 소셜 로그인 흐름은 유지한다.
            if (claims.get("firebase", {}).get("sign_in_provider") == "password"
                    and claims.get("email_verified") is not True):
                raise HTTPException(403, "회원가입 이메일 인증을 먼저 완료해 주세요.")
            # 이메일과 UID는 검증된 토큰에서만 얻고, 내부 ID는 서버 UUID로 생성한다.
            email = claims.get("email")
            if not isinstance(email, str) or not email or len(email) > 200:
                raise HTTPException(422, "로그인 계정의 이메일을 확인해 주세요.")
            # 비밀번호는 Firebase가 관리하므로 INSERT에서 제외해 NULL로 둔다.
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
        # 응답용 행까지 확인한 뒤 저장을 확정한다. 이전 단계 실패 시 rollback한다.
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
            # 대소문자만 다른 UID 등 다른 계정과의 UNIQUE 충돌은 자동 연결하지 않는다.
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
        # 성공·실패·조기 반환 모두에서 요청의 DB 연결을 정리한다.
        if connection is not None:
            connection.close()


@router.get("/me", response_model=CurrentUserResponse)
def get_current_user(claims: dict = Depends(require_firebase_user)):
    # 사용자 UID를 쿼리 인자에서 받지 않고 인증 의존성이 검증한 claims만 사용한다.
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
        # 조회 성공 후 행이 없는 경우만 미등록이다. DB 오류는 아래에서 503으로 구분한다.
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
