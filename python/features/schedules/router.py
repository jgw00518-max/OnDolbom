from datetime import date, time

from fastapi import APIRouter, Depends, HTTPException, Query
from pydantic import BaseModel, ConfigDict, Field, model_validator
from pymysql import MySQLError

from python.database import connect
from python.features.auth.firebase_auth import require_firebase_user

import logging

from python.features.notifications.schedule_notifications import (
    prepare_schedule_notifications,
    publish_schedule_notifications,
)

from fastapi import APIRouter, Depends, HTTPException, Path, Query

router = APIRouter(
    prefix="/schedules",
    tags=["schedules"],
)
logger = logging.getLogger(__name__)


# 일정 등록 화면에서 전달받는 입력값
class ScheduleCreate(BaseModel):
    model_config = ConfigDict(
        str_strip_whitespace=True,
        extra="forbid",
    )

    family_room_id: str = Field(min_length=1, max_length=50)
    schedule_date: date
    start_time: time
    end_time: time
    schedule_name: str | None = Field(default=None, max_length=50)
    schedule_memo: str | None = None

    # 시작·종료 시간을 검사한다.
    @model_validator(mode="after")
    def validate_times(self):
        # 날짜와 시간을 별도로 저장하므로 시간대 없는 시각을 받는다.
        if (
            self.start_time.tzinfo is not None
            or self.end_time.tzinfo is not None
        ):
            raise ValueError("시간대 없이 시작·종료 시간을 입력해 주세요.")

        if self.start_time >= self.end_time:
            raise ValueError("종료 시간은 시작 시간보다 늦어야 합니다.")

        return self

# A의 Firebase 인증 결과로 MySQL 사용자 ID를 조회한다.
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

    except (MySQLError, ValueError):
        raise HTTPException(
            status_code=503,
            detail="사용자 정보를 확인하지 못했습니다.",
        ) from None

    finally:
        if conn is not None:
            conn.close()

# 현재 공간에 참여 중인 주보호자인지 확인한다.
def check_representative(conn, family_room_id: str, user_id: str):
    with conn.cursor() as cursor:
        # 같은 공간의 일정 등록을 순서대로 처리하도록 공간 행을 잠근다.
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

        # 현재 참여 상태와 주보호자 권한을 확인한다.
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
                detail="현재 공간의 주보호자만 일정을 등록할 수 있습니다.",
            )

# 같은 공간·날짜에 시간이 겹치는 일정이 있는지 확인한다.
def check_schedule_overlap(conn, data: ScheduleCreate):
    with conn.cursor() as cursor:
        cursor.execute(
            """
            SELECT schedule_seq
            FROM create_schedule
            WHERE family_room_id = %s
              AND schedule_date = %s
              AND deleted_at IS NULL
              AND start_time < %s
              AND end_time > %s
            LIMIT 1
            FOR UPDATE
            """,
            (
                data.family_room_id,
                data.schedule_date,
                data.end_time,
                data.start_time,
            ),
        )

        if cursor.fetchone() is not None:
            raise HTTPException(
                status_code=409,
                detail="같은 공간에 시간이 겹치는 일정이 있습니다.",
            )

# 주보호자가 현재 공간의 일정을 등록한다.
@router.post("", status_code=201)
def create_schedule(
    data: ScheduleCreate,
    current_user_id: str = Depends(get_current_user_id),
) -> dict:
    conn = None

    try:
        conn = connect()

        # 같은 연결에서 권한·시간 중복을 검사하고 저장한다.
        check_representative(
            conn,
            data.family_room_id,
            current_user_id,
        )
        check_schedule_overlap(conn, data)

        with conn.cursor() as cursor:
            # 일정 날짜가 없으면 날짜 부모 테이블에 먼저 등록한다.
            cursor.execute(
                """
                INSERT INTO schedule (schedule_date)
                VALUES (%s)
                ON DUPLICATE KEY UPDATE
                    schedule_date = schedule_date
                """,
                (data.schedule_date,),
            )

            cursor.execute(
                """
                INSERT INTO create_schedule (
                    schedule_date,
                    family_room_id,
                    created_by,
                    schedule_name,
                    start_time,
                    end_time,
                    schedule_memo,
                    schedule_state
                )
                VALUES (%s, %s, %s, %s, %s, %s, %s, %s)
                """,
                (
                    data.schedule_date,
                    data.family_room_id,
                    current_user_id,
                    data.schedule_name or None,
                    data.start_time,
                    data.end_time,
                    data.schedule_memo or None,
                    "미완료",
                ),
            )

            schedule_seq = cursor.lastrowid

        # A의 함수: 현재 전체 참여 가족의 알림을 준비한다.
        prepare_schedule_notifications(conn, schedule_seq)

        # 일정 저장과 알림 준비가 성공하면 확정한다.
        conn.commit()

    except HTTPException:
        if conn is not None:
            conn.rollback()
        raise

    except Exception:
        if conn is not None:
            conn.rollback()

        logger.exception("일정 등록 또는 알림 준비 실패")

        raise HTTPException(
            status_code=503,
            detail="일정을 등록하지 못했습니다. 서버 연결과 알림 설정을 확인해 주세요.",
        ) from None

    finally:
        if conn is not None:
            conn.close()

    # 저장이 확정된 다음 알림을 발행한다.
    notification_published = False

    try:
        notification_published = bool(
            publish_schedule_notifications(schedule_seq)
        )

    except Exception:
        # 일정은 이미 저장되었으므로 등록 실패로 응답하지 않는다.
        logger.exception(
            "일정 %s 저장 완료, 알림 발행 재시도 필요",
            schedule_seq,
        )

    return {
        "result": "OK",
        "schedule_seq": schedule_seq,
        "schedule_state": "미완료",
        "notification_published": notification_published,
    }

# 현재 참여 중인 가족 공간의 월별 일정을 조회한다.
@router.get("")
def get_schedules(
    family_room_id: str = Query(min_length=1, max_length=50),
    year: int = Query(ge=1900, le=2100),
    month: int = Query(ge=1, le=12),
    current_user_id: str = Depends(get_current_user_id),
) -> dict:
    start_date = date(year, month, 1)
    next_month = date(year + 1, 1, 1) if month == 12 else date(year, month + 1, 1)
    conn = None
    try:
        conn = connect()
        with conn.cursor() as cursor:
            # 일반 가족도 조회할 수 있다. 종료된 참여·계정·공간은 제외한다.
            cursor.execute(
                """SELECT p.participate_seq FROM participate AS p
                   JOIN family_room AS f ON f.family_room_id = p.family_room_id
                   JOIN `user` AS u ON u.user_id = p.user_id
                   WHERE p.family_room_id = %s AND p.user_id = %s
                     AND p.left_at IS NULL AND f.family_room_deleted_at IS NULL
                     AND u.withdrawn_at IS NULL""",
                (family_room_id, current_user_id),
            )
            if cursor.fetchone() is None:
                raise HTTPException(403, "현재 참여 중인 가족 공간만 조회할 수 있습니다.")
            cursor.execute(
                """SELECT s.schedule_seq, s.family_room_id, s.schedule_date,
                          s.schedule_name, CAST(s.start_time AS CHAR) AS start_time,
                          CAST(s.end_time AS CHAR) AS end_time, s.schedule_memo,
                          s.schedule_state, s.created_by, creator.name AS creator_name,
                          s.accepted_by, assignee.name AS accepted_name,
                          s.accepted_at, s.created_at
                   FROM create_schedule AS s
                   LEFT JOIN `user` AS creator ON creator.user_id = s.created_by
                   LEFT JOIN `user` AS assignee ON assignee.user_id = s.accepted_by
                   WHERE s.family_room_id = %s AND s.schedule_date >= %s
                     AND s.schedule_date < %s AND s.deleted_at IS NULL
                   ORDER BY s.schedule_date, s.start_time, s.schedule_seq""",
                (family_room_id, start_date, next_month),
            )
            schedules = cursor.fetchall()
        return {"results": schedules}
    except HTTPException:
        raise
    except (MySQLError, ValueError):
        logger.exception("일정 목록 조회 실패")
        raise HTTPException(503, "일정 목록을 불러오지 못했습니다.") from None
    finally:
        if conn is not None:
            conn.close()

# 현재 공간의 일반 가족 한 명이 일정을 수락한다.
@router.post("/{schedule_seq}/accept")
def accept_schedule(
    schedule_seq: int = Path(gt=0),
    current_user_id: str = Depends(get_current_user_id),
) -> dict:
    conn = None

    try:
        conn = connect()

        with conn.cursor() as cursor:
            # 일정 행을 잠가 동시 수락 요청을 순서대로 처리한다.
            cursor.execute(
                """
                SELECT
                    schedule_seq,
                    family_room_id,
                    accepted_by,
                    schedule_state
                FROM create_schedule
                WHERE schedule_seq = %s
                  AND deleted_at IS NULL
                FOR UPDATE
                """,
                (schedule_seq,),
            )

            schedule = cursor.fetchone()

            if schedule is None:
                raise HTTPException(
                    status_code=404,
                    detail="일정이 없거나 삭제되었습니다.",
                )

            # 현재 참여 중인 가족인지, 공간과 계정이 유효한지 확인한다.
            cursor.execute(
                """
                SELECT p.is_representative
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
                FOR UPDATE
                """,
                (
                    schedule["family_room_id"],
                    current_user_id,
                ),
            )

            member = cursor.fetchone()

            if member is None:
                raise HTTPException(
                    status_code=403,
                    detail="현재 참여 중인 가족 공간의 일정만 수락할 수 있습니다.",
                )

            if member["is_representative"] != 0:
                raise HTTPException(
                    status_code=403,
                    detail="주보호자는 일정을 수락할 수 없습니다.",
                )

            if schedule["schedule_state"] != "미완료":
                raise HTTPException(
                    status_code=409,
                    detail="미완료 일정만 수락할 수 있습니다.",
                )

            if schedule["accepted_by"] is not None:
                raise HTTPException(
                    status_code=409,
                    detail="이미 담당 가족이 등록된 일정입니다.",
                )

            # 수락자를 기록하되 돌봄 완료로 변경하지 않는다.
            cursor.execute(
                """
                UPDATE create_schedule
                SET accepted_by = %s,
                    accepted_at = CURRENT_TIMESTAMP
                WHERE schedule_seq = %s
                  AND accepted_by IS NULL
                  AND deleted_at IS NULL
                  AND schedule_state = %s
                """,
                (
                    current_user_id,
                    schedule_seq,
                    "미완료",
                ),
            )

            if cursor.rowcount != 1:
                raise HTTPException(
                    status_code=409,
                    detail="일정 상태가 변경되었습니다. 다시 조회해 주세요.",
                )

        conn.commit()

        return {
            "result": "OK",
            "schedule_seq": schedule_seq,
            "accepted_by": current_user_id,
            "schedule_state": "미완료",
        }

    except HTTPException:
        if conn is not None:
            conn.rollback()
        raise

    except (MySQLError, ValueError):
        if conn is not None:
            conn.rollback()

        logger.exception("일정 수락 실패")

        raise HTTPException(
            status_code=503,
            detail="일정을 수락하지 못했습니다. 다시 시도해 주세요.",
        ) from None

    finally:
        if conn is not None:
            conn.close()