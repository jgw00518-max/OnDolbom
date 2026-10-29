from datetime import date
from uuid import uuid4

from fastapi import APIRouter, HTTPException, Path
from pydantic import BaseModel, Field, field_validator

from python.database import connect
from python.features.family_room.membership import end_membership

import os

from fastapi import Depends, Header, HTTPException

from pymysql import MySQLError
from python.features.auth.firebase_auth import require_firebase_user
from python.features.chats.connection_manager import manager as chat_manager
from starlette.concurrency import run_in_threadpool


router = APIRouter()


def _soft_delete_family_room(family_room_id: str, user_id: str) -> dict:
    """공간과 권한을 잠근 뒤 공간 삭제 시각만 기록한다. 연결 데이터는 보존한다."""
    connection = None
    try:
        connection = connect()
        with connection.cursor() as cursor:
            # 초대 수락·대상자 수정과 동일하게 공간부터 잠근다.
            cursor.execute('''SELECT family_room_deleted_at FROM family_room
                WHERE family_room_id = %s FOR UPDATE''', (family_room_id,))
            room = cursor.fetchone()
            if room is None:
                raise HTTPException(404, "가족 공간을 찾을 수 없습니다.")
            cursor.execute('''SELECT p.participate_seq, p.is_representative
                FROM participate AS p JOIN `user` AS u ON u.user_id = p.user_id
                WHERE p.family_room_id = %s AND p.user_id = %s
                  AND p.is_active = 1 AND p.left_at IS NULL
                  AND u.withdrawn_at IS NULL
                LIMIT 1 FOR UPDATE''', (family_room_id, user_id))
            member = cursor.fetchone()
            if member is None or member["is_representative"] != 1:
                raise HTTPException(403, "현재 공간의 주보호자만 가족 공간을 삭제할 수 있습니다.")
            deleted_at = room["family_room_deleted_at"]
            already_deleted = deleted_at is not None
            if not already_deleted:
                cursor.execute('''UPDATE family_room
                    SET family_room_deleted_at = CURRENT_TIMESTAMP
                    WHERE family_room_id = %s AND family_room_deleted_at IS NULL''',
                               (family_room_id,))
                cursor.execute('''SELECT family_room_deleted_at FROM family_room
                    WHERE family_room_id = %s''', (family_room_id,))
                deleted_at = cursor.fetchone()["family_room_deleted_at"]
        connection.commit()
        return {"result": "OK", "family_room_id": family_room_id,
                "family_room_deleted_at": deleted_at, "already_deleted": already_deleted}
    except HTTPException:
        if connection is not None:
            connection.rollback()
        raise
    except (MySQLError, ValueError):
        if connection is not None:
            connection.rollback()
        raise HTTPException(503, "가족 공간을 삭제하지 못했습니다. 잠시 후 다시 시도해 주세요.") from None
    finally:
        if connection is not None:
            connection.close()


# 화면에서 입력받는 대상자 정보
class FamilyRoomCreate(BaseModel):
    care_recipient_name: str = Field(min_length=1, max_length=30)
    gender: int = Field(ge=1, le=2)
    birth_date: date | None = None
    care_address: str | None = Field(default=None, max_length=255)
    special_notes: str | None = None

    @field_validator("care_recipient_name")
    @classmethod
    def validate_name(cls, value: str) -> str:
        value = value.strip()

        if not value:
            raise ValueError("대상자 이름을 입력해 주세요.")

        return value

# 대상자 정보 편집 화면에서 전달받는 값
class FamilyRecipientUpdate(BaseModel):
    care_recipient_name: str = Field(min_length=1, max_length=30)
    gender: int = Field(ge=1, le=2)
    birth_date: date | None = None
    care_address: str | None = Field(default=None, max_length=255)
    special_notes: str | None = None

    @field_validator("care_recipient_name")
    @classmethod
    def validate_name(cls, value: str) -> str:
        value = value.strip()

        if not value:
            raise ValueError("대상자 이름을 입력해 주세요.")

        return value

    @field_validator("birth_date")
    @classmethod
    def validate_birth_date(cls, value: date | None) -> date | None:
        if value is not None and value > date.today():
            raise ValueError("생년월일은 미래 날짜로 입력할 수 없습니다.")

        return value
# 로그인 확인을 완료한 사용자 ID를 전달받아 실행한다.
# 아직 API 주소에는 연결하지 않는다.
def create_family_room(
    data: FamilyRoomCreate,
    current_user_id: str,
) -> dict:
    conn = connect()

    try:
        with conn.cursor() as cursor:
            # 존재하는 계정인지 확인한다.
            # 이 조회가 로그인 인증을 대신하는 것은 아니다.
            cursor.execute(
                """
                SELECT user_id
                FROM `user`
                WHERE user_id = %s
                  AND withdrawn_at IS NULL
                FOR UPDATE
                """,
                (current_user_id,),
            )

            user = cursor.fetchone()

            if user is None:
                raise HTTPException(
                    status_code=403,
                    detail="이용 가능한 사용자 계정이 아닙니다.",
                )

            # 서버에서 중복 가능성이 낮은 공간 ID를 생성한다.
            family_room_id = str(uuid4())

            # 1. 대상자 정보와 가족 공간을 저장한다.
            cursor.execute(
                """
                INSERT INTO family_room (
                    family_room_id,
                    care_recipient_name,
                    gender,
                    birth_date,
                    care_address,
                    special_notes,
                    created_by
                )
                VALUES (%s, %s, %s, %s, %s, %s, %s)
                """,
                (
                    family_room_id,
                    data.care_recipient_name,
                    data.gender,
                    data.birth_date,
                    data.care_address,
                    data.special_notes,
                    current_user_id,
                ),
            )

            # 2. 공간 생성자를 주보호자로 등록한다.
            cursor.execute(
                """
                INSERT INTO participate (
                    user_id,
                    family_room_id,
                    is_representative
                )
                VALUES (%s, %s, %s)
                """,
                (
                    current_user_id,
                    family_room_id,
                    1,
                ),
            )

            # 저장한 공간 정보를 조회한다.
            cursor.execute(
                """
                SELECT
                    family_room_id,
                    care_recipient_name,
                    gender,
                    birth_date,
                    care_address,
                    latitude,
                    longitude,
                    special_notes,
                    created_at,
                    family_room_deleted_at,
                    created_by
                FROM family_room
                WHERE family_room_id = %s
                """,
                (family_room_id,),
            )

            room = cursor.fetchone()

            # 저장한 주보호자 참여 정보를 조회한다.
            cursor.execute(
                """
                SELECT
                    participate_seq,
                    user_id,
                    family_room_id,
                    is_representative,
                    joined_at,
                    left_at
                FROM participate
                WHERE user_id = %s
                  AND family_room_id = %s
                  AND left_at IS NULL
                """,
                (
                    current_user_id,
                    family_room_id,
                ),
            )

            participation = cursor.fetchone()

        # 공간과 주보호자 등록이 모두 성공하면 저장한다.
        conn.commit()

        return {
            "result": "OK",
            "family_room": room,
            "participate": participation,
        }

    except HTTPException:
        conn.rollback()
        raise

    except Exception:
        # 참여 등록 등이 실패하면 공간 생성도 취소한다.
        conn.rollback()

        raise HTTPException(
            status_code=500,
            detail="가족 공간 생성 중 오류가 발생했습니다.",
        ) from None

    finally:
        conn.close()

# A의 로그인 검증 결과로 MySQL 사용자 ID를 찾는다.
def get_current_user_id(
    claims: dict = Depends(require_firebase_user),
) -> str:
    conn = None

    try:
        conn = connect()

        with conn.cursor() as cursor:
            cursor.execute(
                """
                SELECT user_id, withdrawn_at
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

        return user["user_id"]

    except HTTPException:
        raise

    except (MySQLError, ValueError):
        raise HTTPException(
            status_code=503,
            detail="사용자 정보를 확인하지 못했습니다.",
        ) from None

    finally:
        if conn is not None:
            conn.close()

# 공간 소프트 삭제. 이미 삭제된 공간도 현재 주보호자만 재요청할 수 있다.
@router.delete("/{family_room_id}")
async def delete_family_room(
    family_room_id: str = Path(min_length=1, max_length=50, pattern=r"^\S+$"),
    current_user_id: str = Depends(get_current_user_id),
) -> dict:
    result = await run_in_threadpool(_soft_delete_family_room, family_room_id, current_user_id)
    # DB 삭제가 확정된 이후에만 연결을 닫는다. 실패 시 연결을 건드리지 않는다.
    await chat_manager.close_room(family_room_id, code=4403)
    return result


# DB 참여 종료가 확정된 사용자만 이 프로세스의 채팅 연결에서 제외한다.
@router.post("/{family_room_id}/leave")
async def leave_family_room(
    family_room_id: str = Path(min_length=1, max_length=50),
    current_user_id: str = Depends(get_current_user_id),
):
    result = await run_in_threadpool(end_membership, family_room_id, current_user_id)
    await chat_manager.close_member(family_room_id, result['user_id'])
    return result


@router.post("/{family_room_id}/members/{participate_seq}/remove")
async def remove_family_member(
    family_room_id: str = Path(min_length=1, max_length=50),
    participate_seq: int = Path(gt=0),
    current_user_id: str = Depends(get_current_user_id),
):
    result = await run_in_threadpool(end_membership, family_room_id, current_user_id, participate_seq)
    await chat_manager.close_member(family_room_id, result['user_id'])
    return result


# 공간 생성 API
@router.post("", status_code=201)
def create_family_room_api(
    data: FamilyRoomCreate,
    # 변경 후
current_user_id: str = Depends(get_current_user_id),
) -> dict:
    # 기존 함수에서 사용자 존재 여부를 확인하고,
    # 공간과 주보호자 참여 정보를 함께 저장한다.
    return create_family_room(
        data=data,
        current_user_id=current_user_id,
    )

# 현재 사용자가 참여 중인 가족 공간 목록
@router.get("")
def get_family_rooms(
    # 변경 후
current_user_id: str = Depends(get_current_user_id),
) -> dict:
    conn = connect()

    try:
        with conn.cursor() as cursor:
            # 이용 가능한 사용자 계정인지 확인한다.
            cursor.execute(
                """
                SELECT user_id
                FROM `user`
                WHERE user_id = %s
                  AND withdrawn_at IS NULL
                """,
                (current_user_id,),
            )

            if cursor.fetchone() is None:
                raise HTTPException(
                    status_code=403,
                    detail="이용 가능한 사용자 계정이 아닙니다.",
                )

            # 참여가 유지되고 삭제되지 않은 공간만 조회한다.
            cursor.execute(
                """
                SELECT
                    fr.family_room_id,
                    fr.care_recipient_name,
                    fr.gender,
                    fr.birth_date,
                    fr.care_address,
                    fr.latitude,
                    fr.longitude,
                    fr.special_notes,
                    fr.created_at,
                    fr.family_room_deleted_at,
                    fr.created_by,
                    p.participate_seq,
                    p.user_id,
                    p.is_representative,
                    p.joined_at,
                    p.left_at
                FROM family_room AS fr
                JOIN participate AS p
                    ON fr.family_room_id = p.family_room_id
                WHERE p.user_id = %s
                  AND p.left_at IS NULL
                  AND fr.family_room_deleted_at IS NULL
                ORDER BY fr.created_at DESC, fr.family_room_id
                """,
                (current_user_id,),
            )

            rows = cursor.fetchall()

        # 공간 데이터와 참여 데이터를 구분해서 반환한다.
        results = []

        for row in rows:
            results.append(
                {
                    "family_room": {
                        "family_room_id": row["family_room_id"],
                        "care_recipient_name": row["care_recipient_name"],
                        "gender": row["gender"],
                        "birth_date": row["birth_date"],
                        "care_address": row["care_address"],
                        "latitude": row["latitude"],
                        "longitude": row["longitude"],
                        "special_notes": row["special_notes"],
                        "created_at": row["created_at"],
                        "family_room_deleted_at": row[
                            "family_room_deleted_at"
                        ],
                        "created_by": row["created_by"],
                    },
                    "participate": {
                        "participate_seq": row["participate_seq"],
                        "user_id": row["user_id"],
                        "family_room_id": row["family_room_id"],
                        "is_representative": row["is_representative"],
                        "joined_at": row["joined_at"],
                        "left_at": row["left_at"],
                    },
                }
            )

        return {"results": results}

    except HTTPException:
        raise

    except Exception:
        raise HTTPException(
            status_code=500,
            detail="가족 공간 목록을 불러오지 못했습니다.",
        ) from None

    finally:
        conn.close()

# 현재 공간에 참여 중인 가족과 역할을 조회한다.
@router.get("/{family_room_id}/members")
def get_family_members(
    family_room_id: str,
    current_user_id: str = Depends(get_current_user_id),
) -> dict:
    conn = None

    try:
        conn = connect()

        with conn.cursor() as cursor:
            # 로그인한 사용자가 현재 공간에 참여 중인지 검사한다.
            cursor.execute(
                """
                SELECT p.participate_seq
                FROM participate AS p
                JOIN family_room AS f
                  ON f.family_room_id = p.family_room_id
                JOIN `user` AS u
                  ON u.user_id = p.user_id
                WHERE p.family_room_id = %s
                  AND p.user_id = %s
                  AND p.left_at IS NULL
                  AND f.family_room_deleted_at IS NULL
                  AND u.withdrawn_at IS NULL
                FOR SHARE
                """,
                (family_room_id, current_user_id),
            )

            if cursor.fetchone() is None:
                raise HTTPException(
                    status_code=403,
                    detail="현재 참여 중인 가족 공간만 조회할 수 있습니다.",
                )

            # 현재 참여 가족만 조회하고 주보호자를 먼저 표시한다.
            cursor.execute(
                """
                SELECT
                    p.participate_seq,
                    p.user_id,
                    p.is_representative,
                    p.joined_at,
                    u.name,
                    u.user_email
                FROM participate AS p
                JOIN `user` AS u
                  ON u.user_id = p.user_id
                WHERE p.family_room_id = %s
                  AND p.left_at IS NULL
                  AND u.withdrawn_at IS NULL
                ORDER BY
                    p.is_representative DESC,
                    p.joined_at,
                    p.participate_seq
                """,
                (family_room_id,),
            )

            members = cursor.fetchall()

        return {"results": members}

    except HTTPException:
        raise

    except (MySQLError, ValueError):
        raise HTTPException(
            status_code=503,
            detail="가족 목록을 불러오지 못했습니다.",
        ) from None

    finally:
        if conn is not None:
            conn.close()

# 현재 주보호자가 해당 공간의 대상자 정보를 수정한다.
@router.put("/{family_room_id}/recipient")
def update_family_recipient(
    family_room_id: str,
    data: FamilyRecipientUpdate,
    current_user_id: str = Depends(get_current_user_id),
) -> dict:
    conn = None

    try:
        conn = connect()

        with conn.cursor() as cursor:
            # 공간을 잠그고 삭제 여부를 검사한다.
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

            # 최초 작성자가 아니라 현재 주보호자 권한으로 검사한다.
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
                (family_room_id, current_user_id),
            )

            member = cursor.fetchone()

            if member is None or member["is_representative"] != 1:
                raise HTTPException(
                    status_code=403,
                    detail="현재 공간의 주보호자만 대상자 정보를 수정할 수 있습니다.",
                )

            # 선택 입력값은 공백만 있으면 NULL로 저장한다.
            address = (data.care_address or "").strip() or None
            notes = (data.special_notes or "").strip() or None

            # 주소가 변경되면 이전 주소의 좌표는 비운다.
            # 최초 생성자 정보는 유지하고 성별은 선택한 값으로 저장한다.
            cursor.execute(
                """
                UPDATE family_room
                SET care_recipient_name = %s,
                    gender = %s,
                    birth_date = %s,
                    latitude = CASE
                        WHEN care_address <=> %s THEN latitude
                        ELSE NULL
                    END,
                    longitude = CASE
                        WHEN care_address <=> %s THEN longitude
                        ELSE NULL
                    END,
                    care_address = %s,
                    special_notes = %s
                WHERE family_room_id = %s
                  AND family_room_deleted_at IS NULL
                """,
                (
                    data.care_recipient_name,
                    data.gender,
                    data.birth_date,
                    address,
                    address,
                    address,
                    notes,
                    family_room_id,
                ),
            )

        conn.commit()

        return {
            "result": "OK",
            "family_room_id": family_room_id,
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
            detail="대상자 정보를 수정하지 못했습니다.",
        ) from None

    finally:
        if conn is not None:
            conn.close()
