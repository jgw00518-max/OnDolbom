from datetime import date
from uuid import uuid4

from fastapi import APIRouter, HTTPException
from pydantic import BaseModel, Field, field_validator

from python.database import connect

import os

from fastapi import Depends, Header, HTTPException


router = APIRouter()


# 화면에서 입력받는 대상자 정보
class FamilyRoomCreate(BaseModel):
    care_recipient_name: str = Field(min_length=1, max_length=30)
    gender: int | None = None
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

# 개발 중에만 Swagger에서 테스트 사용자 ID를 받는다.
def get_dev_user_id(
    x_dev_user_id: str | None = Header(default=None),
) -> str:
    # 환경변수로 명시적으로 켜지 않으면 사용하지 못한다.
    if os.getenv("ENABLE_DEV_AUTH") != "true":
        raise HTTPException(
            status_code=403,
            detail="개발용 사용자 확인 기능이 꺼져 있습니다.",
        )

    if x_dev_user_id is None or not x_dev_user_id.strip():
        raise HTTPException(
            status_code=400,
            detail="테스트 사용자 ID를 입력해 주세요.",
        )

    return x_dev_user_id.strip()

# Depends(get_dev_user_id) 부분을 
# 공간 생성 API
@router.post("", status_code=201)
def create_family_room_api(
    data: FamilyRoomCreate,
    current_user_id: str = Depends(get_dev_user_id),
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
    current_user_id: str = Depends(get_dev_user_id),
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