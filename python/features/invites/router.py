from typing import Literal
from python.features.invites.history import visible_history, delete_history
from uuid import uuid4

from fastapi import APIRouter, Depends, HTTPException
from pydantic import BaseModel, ConfigDict, Field, field_validator
from pymysql import MySQLError

from python.database import connect
from python.features.chats.read_status import initialize as initialize_chat_read
from python.features.auth.firebase_auth import require_firebase_user

from python.features.invites.send_email import send_invite_email

import logging
import smtplib


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
                detail="이용할 수 없는 돌봄 공간입니다.",
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
# SMTP 발송과 발송 상태 확정은 신규 생성·만료 재요청에서 함께 사용한다.
@router.post("", status_code=201)
def create_invite(
    data: InviteCreate,
    current_user: dict = Depends(get_current_user),
) -> dict:
    return _create_invite(data, current_user)


@router.post("/{invite_id}/resend", status_code=201)
def resend_invite(invite_id: str, current_user: dict = Depends(get_current_user)) -> dict:
    """원래 발신자가 만료 초대 대신 새 초대를 만들고 이메일을 다시 보낸다."""
    return _create_invite(None, current_user, resend_invite_id=invite_id)


def _create_invite(data, current_user, resend_invite_id=None):
    conn = None

    try:
        conn = connect()

        if resend_invite_id is not None:
            # 공간 → 초대 순서로 잠그기 위해 먼저 본인 초대의 공간만 조회한다.
            with conn.cursor() as cursor:
                cursor.execute("""SELECT family_room_id FROM invite
                    WHERE invite_id=%s AND inviter_id=%s AND invite_deleted_at IS NULL""",
                    (resend_invite_id, current_user["user_id"]))
                source = cursor.fetchone()
            if source is None:
                raise HTTPException(404, "본인이 보낸 초대가 없거나 확인할 수 없습니다.")
            check_inviter(conn, source["family_room_id"], current_user["user_id"])
            with conn.cursor() as cursor:
                cursor.execute("""SELECT family_room_id, invite_email, invite_status,
                    DATE_ADD(invite_at, INTERVAL 7 DAY) <= CURRENT_TIMESTAMP AS expired
                    FROM invite WHERE invite_id=%s AND inviter_id=%s
                    AND family_room_id=%s AND invite_deleted_at IS NULL FOR UPDATE""",
                    (resend_invite_id, current_user["user_id"], source["family_room_id"]))
                original = cursor.fetchone()
            if original is None:
                raise HTTPException(404, "초대가 없거나 확인할 수 없습니다.")
            if not (original["invite_status"] == "만료" or
                    (original["invite_status"] == "대기" and original["expired"])):
                raise HTTPException(409, "만료된 초대만 재요청할 수 있습니다.")
            # 수신 이메일·공간은 요청 본문으로 바꾸지 않고 기존 초대에서 결정한다.
            data = InviteCreate(family_room_id=original["family_room_id"],
                                invite_email=original["invite_email"])

        if resend_invite_id is None:
            check_inviter(conn, data.family_room_id, current_user["user_id"])

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
            
            # 발송 성공 후 7일이 지난 대기 초대를 만료 처리한다.
            cursor.execute(
                """
                UPDATE invite
                SET invite_status = %s
                WHERE family_room_id = %s
                  AND LOWER(TRIM(invite_email)) = %s
                  AND invite_status = %s
                  AND invite_deleted_at IS NULL
                  AND DATE_ADD(invite_at, INTERVAL 7 DAY)
                      <= CURRENT_TIMESTAMP
                """,
                (
                    "만료",
                    data.family_room_id,
                    invite_email,
                    "대기",
                ),
            )
            # 같은 공간·이메일의 대기 초대를 중복 생성하지 않는다.
            cursor.execute(
                """
                SELECT invite_id
                FROM invite
                WHERE family_room_id = %s
                  AND LOWER(TRIM(invite_email)) = %s
                  AND invite_status IN (%s, %s)
                  AND invite_deleted_at IS NULL
                LIMIT 1
                FOR UPDATE
                """,
                (
                    data.family_room_id,
                    invite_email,
                    "대기",
                    "발송대기",
                ),
            )

            if cursor.fetchone() is not None:
                raise HTTPException(
                    status_code=409,
                    detail="이미 대기 중이거나 발송 중인 초대가 있습니다.",
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
                    "발송대기",
                ),
            )

         # 초대 내역을 발송대기 상태로 먼저 저장한다.
        conn.commit()

        email_sent = False
        invite_status = "발송실패"

        try:
            send_invite_email(invite_email)
            email_sent = True
            invite_status = "대기"

        except (smtplib.SMTPException, OSError, ValueError):
            logging.warning("초대 이메일 발송에 실패했습니다.")

        with conn.cursor() as cursor:
            if email_sent:
                # 발송에 성공한 시각부터 유효기간을 계산한다.
                cursor.execute(
                    """
                    UPDATE invite
                    SET invite_at = CURRENT_TIMESTAMP,
                        invite_status = %s
                    WHERE invite_id = %s
                      AND invite_status = %s
                      AND invite_deleted_at IS NULL
                    """,
                    (
                        "대기",
                        invite_id,
                        "발송대기",
                    ),
                )
            else:
                # 실패한 초대는 수락 가능한 대기 상태로 두지 않는다.
                cursor.execute(
                    """
                    UPDATE invite
                    SET invite_status = %s
                    WHERE invite_id = %s
                      AND invite_status = %s
                      AND invite_deleted_at IS NULL
                    """,
                    (
                        "발송실패",
                        invite_id,
                        "발송대기",
                    ),
                )

        conn.commit()

        return {
            "result": "OK",
            "invite_id": invite_id,
            "invite_status": invite_status,
            "email_sent": email_sent,
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
            # 로그인한 이메일의 유효기간이 지난 초대를 만료 처리한다.
            cursor.execute(
                """
                UPDATE invite
                SET invite_status = %s
                WHERE LOWER(TRIM(invite_email)) = %s
                  AND invite_status = %s
                  AND invite_deleted_at IS NULL
                  AND DATE_ADD(invite_at, INTERVAL 7 DAY)
                      <= CURRENT_TIMESTAMP
                """,
                ("만료", email, "대기"),
            )
            cursor.execute(
                """
                SELECT
                    i.invite_id,
                    i.family_room_id,
                    i.invite_email,
                    i.invite_at,
                    DATE_ADD(i.invite_at, INTERVAL 7 DAY) AS expires_at,
                    i.invite_status,
                    f.care_recipient_name,
                    u.name AS inviter_name
                FROM invite AS i
                JOIN family_room AS f
                  ON f.family_room_id = i.family_room_id
                JOIN `user` AS u
                  ON u.user_id = i.inviter_id
                WHERE LOWER(TRIM(i.invite_email)) = %s
                  AND i.invite_status IN (%s, %s, %s, %s, %s)
                  AND i.invite_deleted_at IS NULL
                  AND f.family_room_deleted_at IS NULL
                  AND u.withdrawn_at IS NULL
                ORDER BY i.invite_at DESC, i.invite_id
                """,
                (email, "대기", "만료", "수락", "거절", "취소"),
            )

            invites = cursor.fetchall()

        conn.commit()

        return {"results": visible_history(invites, current_user["user_id"], "received")}

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
            # 잠글 돌봄 공간을 먼저 확인한다.
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
                    detail="이용할 수 없는 돌봄 공간입니다.",
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
            # 이미 만료 처리된 초대는 수락할 수 없다.
            if invite["invite_status"] == "만료":
                raise HTTPException(
                    status_code=409,
                    detail="유효기간이 지난 초대입니다. 주보호자에게 다시 초대를 요청해 주세요.",
                )

            # 화면을 열어둔 사이 유효기간이 지났는지도 확인한다.
            cursor.execute(
                """
                UPDATE invite
                SET invite_status = %s
                WHERE invite_id = %s
                  AND family_room_id = %s
                  AND invite_status = %s
                  AND invite_deleted_at IS NULL
                  AND DATE_ADD(invite_at, INTERVAL 7 DAY)
                      <= CURRENT_TIMESTAMP
                """,
                (
                    "만료",
                    invite_id,
                    family_room_id,
                    "대기",
                ),
            )

            if cursor.rowcount == 1:
                # 만료 상태를 확정한 다음 수락을 차단한다.
                conn.commit()

                raise HTTPException(
                    status_code=409,
                    detail="유효기간이 지난 초대입니다. 주보호자에게 다시 초대를 요청해 주세요.",
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
                    detail="이미 참여 중인 돌봄 공간입니다.",
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

            # 기존 대화는 조회할 수 있지만 신규 참여 전 메시지는 미읽음에 넣지 않는다.
            initialize_chat_read(cursor, cursor.lastrowid, family_room_id)

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
                  AND DATE_ADD(invite_at, INTERVAL 7 DAY)
                      > CURRENT_TIMESTAMP
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

# 받은 초대를 거절한다.
@router.post("/{invite_id}/reject")
def reject_invite(
    invite_id: str,
    current_user: dict = Depends(get_current_user),
) -> dict:
    email = (current_user["user_email"] or "").strip().lower()
    conn = None

    if not email:
        raise HTTPException(
            status_code=403,
            detail="사용자 이메일을 확인할 수 없습니다.",
        )

    try:
        conn = connect()

        with conn.cursor() as cursor:
            # 본인에게 온 초대인지 확인하고 공간 ID를 가져온다.
            cursor.execute(
                """
                SELECT family_room_id
                FROM invite
                WHERE invite_id = %s
                  AND LOWER(TRIM(invite_email)) = %s
                  AND invite_deleted_at IS NULL
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

            # 수락 처리와 동일하게 공간부터 잠근다.
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
                    detail="이용할 수 없는 돌봄 공간입니다.",
                )

            # 수락·거절 요청이 동시에 처리되지 않도록 초대를 잠근다.
            cursor.execute(
                """
                SELECT invite_status
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

            if invite["invite_status"] == "만료":
                raise HTTPException(
                    status_code=409,
                    detail="유효기간이 지난 초대입니다.",
                )

            if invite["invite_status"] != "대기":
                raise HTTPException(
                    status_code=409,
                    detail="이미 처리되었거나 발송이 완료되지 않은 초대입니다.",
                )

            # 거절 직전에도 만료 여부를 확인한다.
            cursor.execute(
                """
                UPDATE invite
                SET invite_status = %s
                WHERE invite_id = %s
                  AND family_room_id = %s
                  AND invite_status = %s
                  AND invite_deleted_at IS NULL
                  AND DATE_ADD(invite_at, INTERVAL 7 DAY)
                      <= CURRENT_TIMESTAMP
                """,
                ("만료", invite_id, family_room_id, "대기"),
            )

            if cursor.rowcount == 1:
                conn.commit()

                raise HTTPException(
                    status_code=409,
                    detail="유효기간이 지난 초대입니다.",
                )

            # 아직 유효한 초대만 거절한다.
            cursor.execute(
                """
                UPDATE invite
                SET invite_status = %s
                WHERE invite_id = %s
                  AND family_room_id = %s
                  AND invite_status = %s
                  AND invite_deleted_at IS NULL
                  AND DATE_ADD(invite_at, INTERVAL 7 DAY)
                      > CURRENT_TIMESTAMP
                """,
                ("거절", invite_id, family_room_id, "대기"),
            )

            if cursor.rowcount != 1:
                raise HTTPException(
                    status_code=409,
                    detail="초대 상태가 변경되었거나 유효기간이 지났습니다. 다시 조회해 주세요.",
                )

        conn.commit()

        return {
            "result": "OK",
            "invite_id": invite_id,
            "invite_status": "거절",
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
            detail="초대를 거절하지 못했습니다.",
        ) from None

    finally:
        if conn is not None:
            conn.close()

# 현재 참여 중인 공간에서 본인이 보낸 초대만 조회한다.
@router.get("/sent")
def get_sent_invites(
    current_user: dict = Depends(get_current_user),
) -> dict:
    user_id = current_user["user_id"]
    conn = None

    try:
        conn = connect()

        with conn.cursor() as cursor:
            # 본인이 보낸 대기 초대만 조회 시 만료 처리한다.
            cursor.execute(
                """
                UPDATE invite AS i
                JOIN family_room AS f
                  ON f.family_room_id = i.family_room_id
                JOIN participate AS p
                  ON p.family_room_id = i.family_room_id
                SET i.invite_status = %s
                WHERE p.user_id = %s
                  AND i.inviter_id = p.user_id
                  AND p.left_at IS NULL
                  AND f.family_room_deleted_at IS NULL
                  AND i.invite_deleted_at IS NULL
                  AND i.invite_status = %s
                  AND DATE_ADD(i.invite_at, INTERVAL 7 DAY)
                      <= CURRENT_TIMESTAMP
                """,
                ("만료", user_id, "대기"),
            )

            # 주보호자 이전은 초대 발신자를 바꾸지 않는다. 본인 발신 기록만 조회한다.
            cursor.execute(
                """
                SELECT DISTINCT
                    i.invite_id,
                    i.family_room_id,
                    i.invite_email,
                    i.invite_at,
                    DATE_ADD(i.invite_at, INTERVAL 7 DAY) AS expires_at,
                    i.invite_status,
                    (i.inviter_id = p.user_id AND p.is_representative = 1 AND i.invite_status = '만료'
                     AND NOT EXISTS (SELECT 1 FROM invite newer
                         WHERE newer.family_room_id=i.family_room_id
                         AND LOWER(TRIM(newer.invite_email))=LOWER(TRIM(i.invite_email))
                         AND newer.invite_deleted_at IS NULL
                         AND (newer.invite_status='발송대기' OR
                              (newer.invite_status='대기' AND
                               DATE_ADD(newer.invite_at, INTERVAL 7 DAY)>CURRENT_TIMESTAMP)))) AS can_resend,
                    (p.is_representative = 1 AND i.invite_status = '대기'
                     AND DATE_ADD(i.invite_at, INTERVAL 7 DAY)>CURRENT_TIMESTAMP) AS can_cancel,
                    f.care_recipient_name,
                    u.name AS inviter_name
                FROM invite AS i
                JOIN family_room AS f
                  ON f.family_room_id = i.family_room_id
                JOIN participate AS p
                  ON p.family_room_id = i.family_room_id
                JOIN `user` AS u
                  ON u.user_id = i.inviter_id
                WHERE p.user_id = %s
                  AND i.inviter_id = p.user_id
                  AND p.left_at IS NULL
                  AND f.family_room_deleted_at IS NULL
                  AND i.invite_deleted_at IS NULL
                ORDER BY i.invite_at DESC, i.invite_id
                """,
                (user_id,),
            )

            invites = cursor.fetchall()

        # 조회 과정에서 변경한 만료 상태를 저장한다.
        conn.commit()

        return {"results": visible_history(invites, current_user["user_id"], "sent")}

    except (MySQLError, ValueError):
        if conn is not None:
            conn.rollback()

        raise HTTPException(
            status_code=503,
            detail="보낸 초대를 불러오지 못했습니다.",
        ) from None

    finally:
        if conn is not None:
            conn.close()

# 현재 주보호자가 아직 수락되지 않은 유효한 초대를 취소한다.
@router.post("/{invite_id}/cancel")
def cancel_invite(
    invite_id: str,
    current_user: dict = Depends(get_current_user),
) -> dict:
    conn = None

    try:
        conn = connect()

        with conn.cursor() as cursor:
            # 취소할 초대의 공간을 확인한다.
            cursor.execute(
                """
                SELECT family_room_id
                FROM invite
                WHERE invite_id = %s
                  AND invite_deleted_at IS NULL
                """,
                (invite_id,),
            )

            invite_room = cursor.fetchone()

            if invite_room is None:
                raise HTTPException(
                    status_code=404,
                    detail="초대가 없거나 확인할 수 없습니다.",
                )

            family_room_id = invite_room["family_room_id"]

        # 공간을 잠그고 현재 참여 중인 주보호자인지 검사한다.
        check_inviter(
            conn,
            family_room_id,
            current_user["user_id"],
        )

        with conn.cursor() as cursor:
            # 수락·거절·취소가 동시에 처리되지 않도록 초대를 잠근다.
            cursor.execute(
                """
                SELECT invite_status
                FROM invite
                WHERE invite_id = %s
                  AND family_room_id = %s
                  AND invite_deleted_at IS NULL
                FOR UPDATE
                """,
                (invite_id, family_room_id),
            )

            invite = cursor.fetchone()

            if invite is None:
                raise HTTPException(
                    status_code=404,
                    detail="초대가 없거나 확인할 수 없습니다.",
                )

            if invite["invite_status"] == "만료":
                raise HTTPException(
                    status_code=409,
                    detail="이미 만료된 초대입니다.",
                )

            if invite["invite_status"] != "대기":
                raise HTTPException(
                    status_code=409,
                    detail="유효한 대기 초대만 취소할 수 있습니다.",
                )

            # 취소 직전 유효기간이 지났다면 만료 상태로 저장한다.
            cursor.execute(
                """
                UPDATE invite
                SET invite_status = %s
                WHERE invite_id = %s
                  AND family_room_id = %s
                  AND invite_status = %s
                  AND invite_deleted_at IS NULL
                  AND DATE_ADD(invite_at, INTERVAL 7 DAY)
                      <= CURRENT_TIMESTAMP
                """,
                ("만료", invite_id, family_room_id, "대기"),
            )

            if cursor.rowcount == 1:
                conn.commit()

                raise HTTPException(
                    status_code=409,
                    detail="이미 만료된 초대입니다.",
                )

            # 아직 유효한 대기 초대만 취소한다.
            cursor.execute(
                """
                UPDATE invite
                SET invite_status = %s
                WHERE invite_id = %s
                  AND family_room_id = %s
                  AND invite_status = %s
                  AND invite_deleted_at IS NULL
                  AND DATE_ADD(invite_at, INTERVAL 7 DAY)
                      > CURRENT_TIMESTAMP
                """,
                ("취소", invite_id, family_room_id, "대기"),
            )

            if cursor.rowcount != 1:
                raise HTTPException(
                    status_code=409,
                    detail="초대 상태가 변경되었거나 만료되었습니다. 다시 조회해 주세요.",
                )

        conn.commit()

        return {
            "result": "OK",
            "invite_id": invite_id,
            "invite_status": "취소",
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
            detail="초대를 취소하지 못했습니다.",
        ) from None

    finally:
        if conn is not None:
            conn.close()

class InviteHistoryDelete(BaseModel):
    model_config = ConfigDict(extra='forbid')
    side: Literal['received', 'sent']
    invite_ids: list[str] = Field(min_length=1, max_length=400)


@router.post('/history/delete')
def delete_invite_history(payload: InviteHistoryDelete,
        current_user: dict = Depends(get_current_user)):
    conn = None
    try:
        conn = connect()
        deleted = delete_history(conn, current_user, payload.side, payload.invite_ids)
        return dict(result='OK', deleted_count=deleted)
    except MySQLError:
        raise HTTPException(503, '초대 기록을 확인하지 못했습니다.') from None
    finally:
        if conn is not None:
            conn.close()
