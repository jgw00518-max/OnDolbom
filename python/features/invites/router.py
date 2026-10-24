from uuid import uuid4

from fastapi import APIRouter, Depends, HTTPException
from pydantic import BaseModel, ConfigDict, Field, field_validator
from pymysql import MySQLError

from python.database import connect
from python.features.auth.firebase_auth import require_firebase_user


router = APIRouter(
    prefix="/invites",
    tags=["invites"],
)


# 주보호자가 초대할 가족의 이메일을 입력한다.
class InviteCreate(BaseModel):
    model_config = ConfigDict(
        str_strip_whitespace=True,
        extra="forbid",
    )

    family_room_id: str = Field(min_length=1, max_length=50)
    invite_email: str = Field(min_length=3, max_length=200)
    @field_validator("invite_email")
    @classmethod
    def validate_email(cls, value: str) -> str:
        if value.count("@") != 1 or any(
            char.isspace() for char in value
        ):
            raise ValueError("올바른 이메일을 입력해 주세요.")

        local, domain = value.split("@")

        if not local or "." not in domain or domain.startswith(".") or domain.endswith("."):
            raise ValueError("올바른 이메일을 입력해 주세요.")

        return value

# A의 Firebase 인증 결과로 현재 사용자 정보를 조회한다.
def get_current_user(
    claims: dict = Depends(require_firebase_user),
) -> dict:
    conn = None

    try:
        conn = connect()

        with conn.cursor() as cursor:
            cursor.execute(
                """
                SELECT
                    user_id,
                    user_email,
                    withdrawn_at
                FROM `user`
                WHERE user_firebase_uid = %s
                  AND BINARY user_firebase_uid = BINARY %s
                LIMIT 1
                """,
                (claims["uid"], claims["uid"]),
            )

            user = cursor.fetchone()

        if user is None:
            raise HTTPException(
                status_code=403,
                detail="사용자 정보 등록을 먼저 완료해 주세요.",
            )

        if user["withdrawn_at"] is not None:
            raise HTTPException(
                status_code=403,
                detail="탈퇴 처리된 계정입니다.",
            )

        return {
            "user_id": user["user_id"],
            "user_email": user["user_email"],
        }

    except (MySQLError, ValueError):
        raise HTTPException(
            status_code=503,
            detail="사용자 정보를 확인하지 못했습니다.",
        ) from None

    finally:
        if conn is not None:
            conn.close()

# 현재 공간의 주보호자만 가족을 초대할 수 있다.
def check_inviter(conn, family_room_id: str, user_id: str):
    with conn.cursor() as cursor:
        # 같은 공간의 초대 처리를 순서대로 진행한다.
        cursor.execute(
            """
            SELECT family_room_id
            FROM family_room
            WHERE family_room_id = %s
              AND family_room_deleted_at IS NULL
            FOR UPDATE
            """,
            (family_room_id,),
        )

        if cursor.fetchone() is None:
            raise HTTPException(
                status_code=403,
                detail="이용할 수 없는 가족 공간입니다.",
            )

        cursor.execute(
            """
            SELECT p.is_representative
            FROM participate AS p
            JOIN `user` AS u
              ON u.user_id = p.user_id
            WHERE p.family_room_id = %s
              AND p.user_id = %s
              AND p.left_at IS NULL
              AND u.withdrawn_at IS NULL
            FOR UPDATE
            """,
            (family_room_id, user_id),
        )

        member = cursor.fetchone()

        if member is None or member["is_representative"] != 1:
            raise HTTPException(
                status_code=403,
                detail="현재 공간의 주보호자만 가족을 초대할 수 있습니다.",
            )
# 주보호자가 가족에게 보낼 초대를 저장한다.
# 실제 이메일 전송은 이후 단계에서 연결한다.
@router.post("", status_code=201)
def create_invite(
    data: InviteCreate,
    current_user: dict = Depends(get_current_user),
) -> dict:
    conn = None

    try:
        conn = connect()

        check_inviter(
            conn,
            data.family_room_id,
            current_user["user_id"],
        )

        # 이메일 비교는 앞뒤 공백과 대소문자를 구분하지 않는다.
        invite_email = data.invite_email.strip().lower()
        my_email = (current_user["user_email"] or "").strip().lower()

        if invite_email == my_email:
            raise HTTPException(
                status_code=409,
                detail="본인에게는 초대를 보낼 수 없습니다.",
            )

        with conn.cursor() as cursor:
            # 이미 참여 중인 가족인지 확인한다.
            cursor.execute(
                """
                SELECT p.participate_seq
                FROM participate AS p
                JOIN `user` AS u
                  ON u.user_id = p.user_id
                WHERE p.family_room_id = %s
                  AND LOWER(TRIM(u.user_email)) = %s
                  AND p.left_at IS NULL
                  AND u.withdrawn_at IS NULL
                LIMIT 1
                FOR UPDATE
                """,
                (
                    data.family_room_id,
                    invite_email,
                ),
            )

            if cursor.fetchone() is not None:
                raise HTTPException(
                    status_code=409,
                    detail="이미 공간에 참여 중인 가족입니다.",
                )

            # 같은 공간·이메일의 대기 초대를 중복 생성하지 않는다.
            cursor.execute(
                """
                SELECT invite_id
                FROM invite
                WHERE family_room_id = %s
                  AND LOWER(TRIM(invite_email)) = %s
                  AND invite_status = %s
                  AND invite_deleted_at IS NULL
                LIMIT 1
                FOR UPDATE
                """,
                (
                    data.family_room_id,
                    invite_email,
                    "대기",
                ),
            )

            if cursor.fetchone() is not None:
                raise HTTPException(
                    status_code=409,
                    detail="이미 대기 중인 초대가 있습니다.",
                )

            invite_id = str(uuid4())

            cursor.execute(
                """
                INSERT INTO invite (
                    invite_id,
                    family_room_id,
                    inviter_id,
                    invite_email,
                    invite_at,
                    invite_status
                )
                VALUES (%s, %s, %s, %s, CURRENT_TIMESTAMP, %s)
                """,
                (
                    invite_id,
                    data.family_room_id,
                    current_user["user_id"],
                    invite_email,
                    "대기",
                ),
            )

        conn.commit()

        return {
            "result": "OK",
            "invite_id": invite_id,
            "invite_status": "대기",
        }

    except HTTPException:
        if conn is not None:
            conn.rollback()
        raise

    except (MySQLError, ValueError):
        if conn is not None:
            conn.rollback()

        raise HTTPException(
            status_code=503,
            detail="초대를 저장하지 못했습니다.",
        ) from None

    finally:
        if conn is not None:
            conn.close()

# 로그인한 사용자 이메일로 받은 대기 초대를 조회한다.
@router.get("/received")
def get_received_invites(
    current_user: dict = Depends(get_current_user),
) -> dict:
    email = (current_user["user_email"] or "").strip().lower()

    if not email:
        raise HTTPException(
            status_code=403,
            detail="사용자 이메일을 확인할 수 없습니다.",
        )

    conn = None

    try:
        conn = connect()

        with conn.cursor() as cursor:
            cursor.execute(
                """
                SELECT
                    i.invite_id,
                    i.family_room_id,
                    i.invite_email,
                    i.invite_at,
                    i.invite_status,
                    f.care_recipient_name,
                    u.name AS inviter_name
                FROM invite AS i
                JOIN family_room AS f
                  ON f.family_room_id = i.family_room_id
                JOIN `user` AS u
                  ON u.user_id = i.inviter_id
                WHERE LOWER(TRIM(i.invite_email)) = %s
                  AND i.invite_status = %s
                  AND i.invite_deleted_at IS NULL
                  AND f.family_room_deleted_at IS NULL
                  AND u.withdrawn_at IS NULL
                ORDER BY i.invite_at DESC, i.invite_id
                """,
                (email, "대기"),
            )

            invites = cursor.fetchall()

        return {"results": invites}

    except HTTPException:
        raise

    except (MySQLError, ValueError):
        raise HTTPException(
            status_code=503,
            detail="받은 초대를 불러오지 못했습니다.",
        ) from None

    finally:
        if conn is not None:
            conn.close()

# 받은 초대를 수락하고 해당 공간의 일반 가족으로 참여한다.
@router.post("/{invite_id}/accept")
def accept_invite(
    invite_id: str,
    current_user: dict = Depends(get_current_user),
) -> dict:
    user_id = current_user["user_id"]
    email = (current_user["user_email"] or "").strip().lower()

    if not email:
        raise HTTPException(
            status_code=403,
            detail="사용자 이메일을 확인할 수 없습니다.",
        )

    conn = None

    try:
        conn = connect()

        with conn.cursor() as cursor:
            # 잠글 가족 공간을 먼저 확인한다.
            cursor.execute(
                """
                SELECT family_room_id
                FROM invite
                WHERE invite_id = %s
                  AND invite_deleted_at IS NULL
                  AND LOWER(TRIM(invite_email)) = %s
                """,
                (invite_id, email),
            )

            invite_room = cursor.fetchone()

            if invite_room is None:
                raise HTTPException(
                    status_code=404,
                    detail="받은 초대가 없거나 확인할 수 없습니다.",
                )

            family_room_id = invite_room["family_room_id"]

            # 초대 생성과 같은 순서로 공간을 먼저 잠근다.
            cursor.execute(
                """
                SELECT family_room_id
                FROM family_room
                WHERE family_room_id = %s
                  AND family_room_deleted_at IS NULL
                FOR UPDATE
                """,
                (family_room_id,),
            )

            if cursor.fetchone() is None:
                raise HTTPException(
                    status_code=403,
                    detail="이용할 수 없는 가족 공간입니다.",
                )

            # 동시 수락 요청을 순서대로 처리한다.
            cursor.execute(
                """
                SELECT invite_status, accepter_id
                FROM invite
                WHERE invite_id = %s
                  AND family_room_id = %s
                  AND LOWER(TRIM(invite_email)) = %s
                  AND invite_deleted_at IS NULL
                FOR UPDATE
                """,
                (invite_id, family_room_id, email),
            )

            invite = cursor.fetchone()

            if invite is None:
                raise HTTPException(
                    status_code=404,
                    detail="받은 초대가 없거나 확인할 수 없습니다.",
                )

            if invite["invite_status"] != "대기":
                raise HTTPException(
                    status_code=409,
                    detail="이미 처리된 초대입니다.",
                )

            # 이미 참여 중인 경우 중복 등록하지 않는다.
            cursor.execute(
                """
                SELECT participate_seq
                FROM participate
                WHERE family_room_id = %s
                  AND user_id = %s
                  AND left_at IS NULL
                FOR UPDATE
                """,
                (family_room_id, user_id),
            )

            if cursor.fetchone() is not None:
                raise HTTPException(
                    status_code=409,
                    detail="이미 참여 중인 가족 공간입니다.",
                )

            # 초대받은 계정을 일반 가족으로 등록한다.
            cursor.execute(
                """
                INSERT INTO participate (
                    user_id,
                    family_room_id,
                    is_representative
                )
                VALUES (%s, %s, %s)
                """,
                (user_id, family_room_id, 0),
            )

            # 참여 등록과 초대 상태 변경을 함께 저장한다.
            cursor.execute(
                """
                UPDATE invite
                SET invite_status = %s,
                    accepter_id = %s,
                    accepted_at = CURRENT_TIMESTAMP
                WHERE invite_id = %s
                  AND family_room_id = %s
                  AND invite_status = %s
                  AND invite_deleted_at IS NULL
                """,
                (
                    "수락",
                    user_id,
                    invite_id,
                    family_room_id,
                    "대기",
                ),
            )

            if cursor.rowcount != 1:
                raise HTTPException(
                    status_code=409,
                    detail="초대 상태가 변경되었습니다. 다시 조회해 주세요.",
                )

        conn.commit()

        return {
            "result": "OK",
            "family_room_id": family_room_id,
            "invite_status": "수락",
        }

    except HTTPException:
        if conn is not None:
            conn.rollback()
        raise

    except (MySQLError, ValueError):
        if conn is not None:
            conn.rollback()

        raise HTTPException(
            status_code=503,
            detail="초대를 수락하지 못했습니다.",
        ) from None

    finally:
        if conn is not None:
            conn.close()