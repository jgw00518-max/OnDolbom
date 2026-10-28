from python.features.schedules.reminders import try_remind
from python.features.schedules.response_notifications import prepare_response_notification, publish_response_notification
from datetime import date, time

from fastapi import APIRouter, Depends, HTTPException, Path, Query
from pydantic import BaseModel, ConfigDict, Field, model_validator
from pymysql import MySQLError

from python.database import connect
from python.features.auth.firebase_auth import require_firebase_user

import logging

from python.features.notifications.schedule_notifications import (
    prepare_schedule_notifications,
    publish_schedule_notifications,
)

from python.features.schedules.notification_router import (
    router as schedule_notifications_router,
)


from python.features.schedules.reconfirm_policy import (
    has_schedule_time_changed,
    get_reconfirm_deadline,
)

from python.features.schedules.change_notifications import (
    prepare_reconfirm_notification,
    publish_reconfirm_notification,
    prepare_schedule_change_notification,
    publish_schedule_change_notification,
    prepare_recruitment_notification,
    publish_recruitment_notification,
)

from python.features.schedules.reconfirm_history import (
    get_pending_reconfirm_request,
)

from python.features.schedules.delete_schedule import (
    get_schedule_for_delete,
    mark_schedule_deleted,
    prepare_schedule_delete_notification,
    publish_schedule_delete_notification,
)

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

# 현재 수정 중인 일정을 제외하고 다른 일정의 최신 내용과 비교한다.
def check_schedule_overlap(
    conn,
    data: ScheduleCreate,
    exclude_schedule_seq: int | None = None,
):
    with conn.cursor() as cursor:
        cursor.execute(
            """
            SELECT s.schedule_seq
            FROM create_schedule AS s
            LEFT JOIN update_schedule AS h
              ON h.schedule_seq = s.schedule_seq
             AND h.history_seq = (
                 SELECT MAX(h2.history_seq)
                 FROM update_schedule AS h2
                 WHERE h2.schedule_seq = s.schedule_seq
             )
            WHERE s.family_room_id = %s
              AND s.deleted_at IS NULL
              AND (%s IS NULL OR s.schedule_seq <> %s)
              AND (
                  CASE WHEN h.history_seq IS NULL
                      THEN s.schedule_date
                      ELSE h.schedule_date
                  END
              ) = %s
              AND (
                  CASE WHEN h.history_seq IS NULL
                      THEN s.start_time
                      ELSE h.updated_start_time
                  END
              ) < %s
              AND (
                  CASE WHEN h.history_seq IS NULL
                      THEN s.end_time
                      ELSE h.updated_end_time
                  END
              ) > %s
            LIMIT 1
            FOR UPDATE
            """,
            (
                data.family_room_id,
                exclude_schedule_seq,
                exclude_schedule_seq,
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

    reminder_published = try_remind(schedule_seq)

    return {
        "result": "OK",
        "schedule_seq": schedule_seq,
        "schedule_state": "미완료",
        "notification_published": notification_published,
        "reminder_published": reminder_published,
    }

# 주보호자가 변경 내용을 새 이력으로 저장한다.
@router.put("/{schedule_seq}")
def update_schedule(
    data: ScheduleCreate,
    schedule_seq: int = Path(gt=0),
    current_user_id: str = Depends(get_current_user_id),
) -> dict:
    conn = None

    try:
        conn = connect()

        # 등록·수락·재수락과 같은 순서로 공간부터 잠근다.
        check_representative(conn, data.family_room_id, current_user_id)

        with conn.cursor() as cursor:
            cursor.execute(
                """
                SELECT
                    schedule_seq,
                    family_room_id,
                    schedule_date,
                    schedule_name,
                    CAST(start_time AS CHAR) AS start_time,
                    CAST(end_time AS CHAR) AS end_time,
                    schedule_memo,
                    schedule_state,
                    accepted_by,
                    accepted_at
                FROM create_schedule
                WHERE schedule_seq = %s
                  AND family_room_id = %s
                  AND deleted_at IS NULL
                FOR UPDATE
                """,
                (schedule_seq, data.family_room_id),
            )
            schedule = cursor.fetchone()

            if schedule is None:
                raise HTTPException(404, "일정이 없거나 삭제되었습니다.")

            if schedule["schedule_state"] != "미완료":
                raise HTTPException(409, "미완료 일정만 변경할 수 있습니다.")

            # 이미 변경된 일정이면 최초 내용 대신 가장 최신 내용과 비교한다.
            cursor.execute(
                """
                SELECT
                    history_seq,
                    update_accepted_by,
                    update_accepted_at,
                    schedule_date,
                    updated_schedule_name AS schedule_name,
                    CAST(updated_start_time AS CHAR) AS start_time,
                    CAST(updated_end_time AS CHAR) AS end_time,
                    updated_schedule_memo AS schedule_memo
                FROM update_schedule
                WHERE schedule_seq = %s
                  AND family_room_id = %s
                ORDER BY history_seq DESC
                LIMIT 1
                FOR UPDATE
                """,
                (schedule_seq, data.family_room_id),
            )
            latest = cursor.fetchone()

        current = latest if latest is not None else schedule
        new_content = {
            "schedule_date": data.schedule_date,
            "schedule_name": data.schedule_name or None,
            "start_time": data.start_time,
            "end_time": data.end_time,
            "schedule_memo": data.schedule_memo or None,
        }

        unchanged = (
            current["schedule_date"] == new_content["schedule_date"]
            and current["schedule_name"] == new_content["schedule_name"]
            and time.fromisoformat(current["start_time"]) == data.start_time
            and time.fromisoformat(current["end_time"]) == data.end_time
            and current["schedule_memo"] == new_content["schedule_memo"]
        )

        if unchanged:
            conn.commit()
            return {
                "result": "OK",
                "schedule_seq": schedule_seq,
                "changed": False,
            }

        # 기존 재수락 대기 요청이 있는지 확인한다.
        pending_request = get_pending_reconfirm_request(
            conn,
            schedule_seq,
            data.family_room_id,
            schedule["accepted_by"],
        )

        # 현재 수정 중인 일정만 제외하고 다른 일정의 최신 시간과 비교한다.
        check_schedule_overlap(conn, data, exclude_schedule_seq=schedule_seq)

        with conn.cursor() as cursor:
            cursor.execute(
                """
                INSERT INTO schedule (schedule_date)
                VALUES (%s)
                ON DUPLICATE KEY UPDATE
                    schedule_date = schedule_date
                """,
                (data.schedule_date,),
            )
        # 날짜·시작·종료시간 중 하나라도 변경됐는지 확인한다.
        time_changed = has_schedule_time_changed(current, new_content)
        # 날짜·시간이 바뀔 때만 새 재수락 요청 알림을 보낸다.
        send_reconfirm_request = (
            schedule["accepted_by"] is not None and time_changed
        )

        # 이름·메모만 바꿔도 기존 재수락 대기 상태는 유지한다.
        reconfirm_required = (
            schedule["accepted_by"] is not None
            and (time_changed or pending_request is not None)
        )

        # 이름·메모만 변경하면 기존 담당자의 수락 시각을 보존한다.
        previous_accepted_at = None

        if schedule["accepted_by"] is not None and not reconfirm_required:
            if (
                latest is not None
                and latest["update_accepted_by"] == schedule["accepted_by"]
            ):
                previous_accepted_at = latest["update_accepted_at"]

            if previous_accepted_at is None:
                previous_accepted_at = schedule["accepted_at"]

            if previous_accepted_at is None:
                raise HTTPException(
                    409,
                    "기존 담당자의 수락 시각을 확인해 주세요.",
                )
        # 최초 내용과 이전 이력은 보존하고 변경 후의 전체 내용을 추가한다.
        # 날짜·시간 변경이면 재수락 대기로, 이름·메모만 변경이면 기존 수락 시각을 유지한다.
        history_seq = insert_schedule_history(
            conn=conn,
            schedule_seq=schedule_seq,
            family_room_id=data.family_room_id,
            changed_by=current_user_id,
            schedule_data=new_content,
            accepted_by=schedule["accepted_by"],
            confirmed=False,
            accepted_at=previous_accepted_at,
        )

        notification_published = False

        # 기존 수락자가 있으면 변경 종류에 맞는 알림을 준비한다.
        if schedule["accepted_by"] is not None:
            try:
                if send_reconfirm_request:
                    prepare_reconfirm_notification(
                        conn,
                        schedule_seq,
                        history_seq,
                    )
                else:
                    prepare_schedule_change_notification(
                        conn,
                        schedule_seq,
                        history_seq,
                    )
            except Exception:
                logger.exception("일정 변경 알림 준비 실패")
                raise HTTPException(
                    503,
                    "알림을 준비하지 못해 일정 변경을 취소했습니다.",
                ) from None

        conn.commit()

        # DB 저장이 확정된 뒤 알림을 발행한다.
        if schedule["accepted_by"] is not None:
            try:
                if send_reconfirm_request:
                    notification_published = publish_reconfirm_notification(
                        schedule_seq,
                        history_seq,
                    )
                else:
                    notification_published = publish_schedule_change_notification(
                        schedule_seq,
                        history_seq,
                    )

                if not notification_published:
                    logger.warning(
                        "일정 %s 변경 이력 %s 알림 발행 확인 필요",
                        schedule_seq,
                        history_seq,
                    )
            except Exception:
                # 이미 저장된 일정 변경은 유지한다.
                logger.exception(
                    "일정 %s 변경 저장 완료, 알림 발행 재시도 필요",
                    schedule_seq,
                )

        reminder_published = try_remind(schedule_seq)

        return {
            "result": "OK",
            "schedule_seq": schedule_seq,
            "history_seq": history_seq,
            "changed": True,
            "reminder_published": reminder_published,
            "reconfirm_required": reconfirm_required,
            "reconfirm_user_id": (
                schedule["accepted_by"] if reconfirm_required else None
            ),
            "notification_published": notification_published,
        }

    except HTTPException:
        if conn is not None:
            conn.rollback()
        raise

    except (MySQLError, ValueError):
        if conn is not None:
            conn.rollback()

        logger.exception("일정 변경 실패")
        raise HTTPException(503, "일정을 변경하지 못했습니다.") from None

    finally:
        if conn is not None:
            conn.close()


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
            # 변경 이력이 있으면 최신 이력을 적용한 일정으로 조회한다.
            cursor.execute(
                """
                SELECT
                    s.schedule_seq,
                    s.family_room_id,
                    s.schedule_date,
                    s.schedule_name,
                    CAST(s.start_time AS CHAR) AS start_time,
                    CAST(s.end_time AS CHAR) AS end_time,
                    s.schedule_memo,
                    s.schedule_state,
                    s.created_by,
                    creator.name AS creator_name,
                    s.accepted_by,
                    assignee.name AS accepted_name,
                    s.accepted_at,
                    s.created_at,
                    s.history_seq,
                    s.reconfirm_required,
                    CASE WHEN s.reconfirm_required = 1
                        THEN s.latest_accepted_by
                        ELSE NULL
                    END AS reconfirm_user_id
                FROM (
                    SELECT
                        b.schedule_seq,
                        b.family_room_id,
                        b.schedule_state,
                        b.created_by,
                        b.accepted_by,
                        b.accepted_at,
                        b.created_at,
                        b.deleted_at,
                        h.history_seq,
                        h.update_accepted_by AS latest_accepted_by,
                        CASE
                            WHEN h.update_accepted_by IS NOT NULL
                             AND h.update_accepted_at IS NULL
                             AND h.update_accepted_by = b.accepted_by
                             AND b.schedule_state = '미완료'
                            THEN 1
                            ELSE 0
                        END AS reconfirm_required,
                        CASE WHEN h.history_seq IS NULL
                            THEN b.schedule_date
                            ELSE h.schedule_date
                        END AS schedule_date,
                        CASE WHEN h.history_seq IS NULL
                            THEN b.schedule_name
                            ELSE h.updated_schedule_name
                        END AS schedule_name,
                        CASE WHEN h.history_seq IS NULL
                            THEN b.start_time
                            ELSE h.updated_start_time
                        END AS start_time,
                        CASE WHEN h.history_seq IS NULL
                            THEN b.end_time
                            ELSE h.updated_end_time
                        END AS end_time,
                        CASE WHEN h.history_seq IS NULL
                            THEN b.schedule_memo
                            ELSE h.updated_schedule_memo
                        END AS schedule_memo
                    FROM create_schedule AS b
                    LEFT JOIN update_schedule AS h
                      ON h.schedule_seq = b.schedule_seq
                     AND h.history_seq = (
                         SELECT MAX(h2.history_seq)
                         FROM update_schedule AS h2
                         WHERE h2.schedule_seq = b.schedule_seq
                     )
                ) AS s
                LEFT JOIN `user` AS creator
                  ON creator.user_id = s.created_by
                LEFT JOIN `user` AS assignee
                  ON assignee.user_id = s.accepted_by
                WHERE s.family_room_id = %s
                  AND s.schedule_date >= %s
                  AND s.schedule_date < %s
                  AND s.deleted_at IS NULL
                ORDER BY s.schedule_date, s.start_time, s.schedule_seq
                """,
                (family_room_id, start_date, next_month),
            )
            schedules = cursor.fetchall()

            for schedule in schedules:
                schedule["previous_schedule"] = None
                schedule["reconfirm_request_history_seq"] = None
                schedule["reconfirm_requested_at"] = None
                schedule["reconfirm_response_due_at"] = None
                schedule["reconfirm_is_urgent"] = False

                if not schedule["reconfirm_required"]:
                    continue

                pending_request = get_pending_reconfirm_request(
                    conn,
                    schedule["schedule_seq"],
                    schedule["family_room_id"],
                    schedule["accepted_by"],
                )

                if pending_request is None:
                    raise ValueError(
                        "현재 재수락 요청 정보를 확인하지 못했습니다."
                    )

                # 메모를 다시 수정해도 최초 요청 직전의 비교 기준을 유지한다.
                schedule["previous_schedule"] = pending_request["before"]

                # 최신 변경 이력과 최초 재수락 요청 번호·시각을 구분한다.
                schedule["reconfirm_request_history_seq"] = (
                    pending_request["request_history_seq"]
                )
                schedule["reconfirm_requested_at"] = (
                    pending_request["requested_at"]
                )
                # 현재 시각이 아닌 최초 요청 시각으로 기한을 계산한다.
                # 메모만 수정해도 응답 기한이 연장되지 않는다.
                deadline = get_reconfirm_deadline(
                    requested_at=pending_request["requested_at"],
                    schedule_date=pending_request["current"]["schedule_date"],
                    start_time=pending_request["current"]["start_time"],
                )

                schedule["reconfirm_response_due_at"] = (
                    deadline["response_due_at"]
                )
                schedule["reconfirm_is_urgent"] = deadline["is_urgent"]

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
            # 변경 처리와 동일하게 공간부터 잠그기 위해 공간 ID를 확인한다.
            cursor.execute(
                """
                SELECT family_room_id
                FROM create_schedule
                WHERE schedule_seq = %s
                  AND deleted_at IS NULL
                """,
                (schedule_seq,),
            )

            schedule_room = cursor.fetchone()

            if schedule_room is None:
                raise HTTPException(
                    status_code=404,
                    detail="일정이 없거나 삭제되었습니다.",
                )

            cursor.execute(
                """
                SELECT family_room_id
                FROM family_room
                WHERE family_room_id = %s
                  AND family_room_deleted_at IS NULL
                FOR UPDATE
                """,
                (schedule_room["family_room_id"],),
            )

            if cursor.fetchone() is None:
                raise HTTPException(
                    status_code=403,
                    detail="이용할 수 없는 가족 공간입니다.",
                )
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
                    detail="이미 담당 가족이 수락한 일정입니다.",
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

        try:
            response_notice = prepare_response_notification(conn, schedule_seq, current_user_id)
        except Exception:
            logger.exception("수락 결과 알림 준비 실패")
            raise HTTPException(503, "알림을 준비하지 못해 수락을 취소했습니다.") from None
        conn.commit()
        # 발행 실패로 이미 확정된 수락을 되돌리지 않는다.
        response_published = False
        try:
            response_published = bool(publish_response_notification(response_notice))
        except Exception:
            logger.exception("수락 완료, 주보호자 알림 발행 확인 필요")

        return {
            "result": "OK",
            "response_notification_published": response_published,
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

# 일정 내용과 담당자 상태를 새 이력으로 저장한다.
# commit과 rollback은 호출한 API에서 처리한다.
def insert_schedule_history(
    conn,
    schedule_seq: int,
    family_room_id: str,
    changed_by: str,
    schedule_data: dict,
    accepted_by: str | None = None,
    confirmed: bool = False,
    accepted_at=None,
) -> int:
    if confirmed and accepted_by is None:
        raise ValueError("수락 완료 이력에는 수락자가 필요합니다.")

    with conn.cursor() as cursor:
        cursor.execute(
            """
            INSERT INTO update_schedule (
                schedule_seq,
                schedule_date,
                family_room_id,
                changed_by,
                update_accepted_by,
                update_accepted_at,
                updated_schedule_name,
                updated_start_time,
                updated_end_time,
                updated_schedule_memo
            )
            VALUES (
                %s, %s, %s, %s, %s,
                CASE WHEN %s = 1
                    THEN CURRENT_TIMESTAMP
                    ELSE %s
                END,
                %s, %s, %s, %s
            )
            """,
            (
                schedule_seq,
                schedule_data["schedule_date"],
                family_room_id,
                changed_by,
                accepted_by,
                confirmed,
                accepted_at,
                schedule_data.get("schedule_name"),
                schedule_data["start_time"],
                schedule_data["end_time"],
                schedule_data.get("schedule_memo"),
            ),
        )

        return cursor.lastrowid

# 재수락이면 true, 거절이면 false를 받는다.
class ScheduleReconfirmAnswer(BaseModel):
    accepted: bool = Field(strict=True)


@router.post("/{schedule_seq}/changes/{history_seq}/respond")
def respond_schedule_change(
    data: ScheduleReconfirmAnswer,
    schedule_seq: int = Path(gt=0),
    history_seq: int = Path(gt=0),
    current_user_id: str = Depends(get_current_user_id),
) -> dict:
    conn = None

    try:
        conn = connect()

        with conn.cursor() as cursor:
            # 공간부터 잠그기 위해 일정의 공간 ID를 확인한다.
            cursor.execute(
                """
                SELECT family_room_id
                FROM create_schedule
                WHERE schedule_seq = %s
                  AND deleted_at IS NULL
                """,
                (schedule_seq,),
            )
            schedule_room = cursor.fetchone()

            if schedule_room is None:
                raise HTTPException(404, "일정이 없거나 삭제되었습니다.")

            family_room_id = schedule_room["family_room_id"]

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
                raise HTTPException(403, "이용할 수 없는 가족 공간입니다.")

            # 현재 배정 상태를 잠금 조회한다.
            cursor.execute(
                """
                SELECT accepted_by, schedule_state
                FROM create_schedule
                WHERE schedule_seq = %s
                  AND family_room_id = %s
                  AND deleted_at IS NULL
                FOR UPDATE
                """,
                (schedule_seq, family_room_id),
            )
            schedule = cursor.fetchone()

            if schedule is None:
                raise HTTPException(404, "일정이 없거나 삭제되었습니다.")

            # 현재 참여 중인 가족인지 확인한다.
            cursor.execute(
                """
                SELECT p.participate_seq
                FROM participate AS p
                JOIN `user` AS u ON u.user_id = p.user_id
                WHERE p.family_room_id = %s
                  AND p.user_id = %s
                  AND p.left_at IS NULL
                  AND u.withdrawn_at IS NULL
                FOR UPDATE
                """,
                (family_room_id, current_user_id),
            )

            if cursor.fetchone() is None:
                raise HTTPException(
                    403,
                    "현재 참여 중인 가족만 응답할 수 있습니다.",
                )

            # 가장 최신 이력을 잠가 중복 응답을 방지한다.
            cursor.execute(
                """
                SELECT
                    history_seq,
                    update_accepted_by,
                    update_accepted_at,
                    schedule_date,
                    updated_schedule_name AS schedule_name,
                    CAST(updated_start_time AS CHAR) AS start_time,
                    CAST(updated_end_time AS CHAR) AS end_time,
                    updated_schedule_memo AS schedule_memo
                FROM update_schedule
                WHERE schedule_seq = %s
                  AND family_room_id = %s
                ORDER BY history_seq DESC
                LIMIT 1
                FOR UPDATE
                """,
                (schedule_seq, family_room_id),
            )
            latest = cursor.fetchone()

            pending_request = get_pending_reconfirm_request(
                conn,
                schedule_seq,
                family_room_id,
                schedule["accepted_by"],
            )

            # 이름·메모만 변경한 이력은 같은 요청으로 취급한다.
            # 날짜·시간을 다시 변경했다면 이전 요청으로 응답할 수 없다.
            if (
                latest is None
                or pending_request is None
                or history_seq not in pending_request["request_history_seqs"]
            ):
                raise HTTPException(
                    409,
                    "변경 요청이 이미 처리되었거나 달라졌습니다. 다시 조회해 주세요.",
                )

            if (
                latest["update_accepted_by"] is None
                or latest["update_accepted_at"] is not None
            ):
                raise HTTPException(
                    409,
                    "응답할 재수락 요청이 없거나 이미 처리되었습니다.",
                )

            if latest["update_accepted_by"] != current_user_id:
                raise HTTPException(
                    403,
                    "본인에게 온 재수락 요청만 응답할 수 있습니다.",
                )

            if (
                schedule["schedule_state"] != "미완료"
                or schedule["accepted_by"] != current_user_id
            ):
                raise HTTPException(
                    409,
                    "일정 상태나 담당자가 변경되었습니다. 다시 조회해 주세요.",
                )
            # 최초 요청 시각과 최신 일정 시작 시각으로 기한을 확인한다.
            deadline = get_reconfirm_deadline(
                requested_at=pending_request["requested_at"],
                schedule_date=pending_request["current"]["schedule_date"],
                start_time=pending_request["current"]["start_time"],
            )

            # 일반·긴급 구분 없이 응답 기한이 있으면 만료 여부를 검사한다.
            if deadline["response_due_at"] is not None:
                cursor.execute(
                    "SELECT CURRENT_TIMESTAMP AS server_now"
                )
                server_now = cursor.fetchone()["server_now"]

                if server_now >= deadline["response_due_at"]:
                    raise HTTPException(
                        409,
                        "재수락 응답 기한이 지났습니다. "
                        "일정을 다시 조회해 주세요.",
                    )
            if not data.accepted:
                # 거절하면 현재 담당 배정을 해제한다.
                cursor.execute(
                    """
                    UPDATE create_schedule
                    SET accepted_by = NULL
                    WHERE schedule_seq = %s
                      AND family_room_id = %s
                      AND accepted_by = %s
                      AND deleted_at IS NULL
                      AND schedule_state = %s
                    """,
                    (
                        schedule_seq,
                        family_room_id,
                        current_user_id,
                        "미완료",
                    ),
                )

                if cursor.rowcount != 1:
                    raise HTTPException(
                        409,
                        "담당자가 변경되었습니다. 다시 조회해 주세요.",
                    )

        # 이전 요청은 유지하고 응답 결과를 새 이력으로 저장한다.
        answer_history_seq = insert_schedule_history(
            conn=conn,
            schedule_seq=schedule_seq,
            family_room_id=family_room_id,
            changed_by=current_user_id,
            schedule_data=latest,
            accepted_by=current_user_id if data.accepted else None,
            confirmed=data.accepted,
        )

        response_notice = None
        if data.accepted:
            try:
                response_notice = prepare_response_notification(conn, schedule_seq, current_user_id, answer_history_seq)
            except Exception:
                logger.exception("재수락 결과 알림 준비 실패")
                raise HTTPException(503, "알림을 준비하지 못해 재수락을 취소했습니다.") from None

        recruitment_notification_published = False

        # 거절한 경우에만 전체 가족 재모집 알림을 준비한다.
        if not data.accepted:
            try:
                prepare_recruitment_notification(
                    conn,
                    schedule_seq,
                    answer_history_seq,
                )
            except Exception:
                logger.exception("거절 후 재모집 알림 준비 실패")
                raise HTTPException(
                    503,
                    "재모집 알림을 준비하지 못해 거절 처리를 취소했습니다.",
                ) from None

        # 배정 해제·응답 이력 저장이 모두 성공해야 확정한다.
        conn.commit()

        response_published = False
        if response_notice is not None:
            try:
                response_published = bool(publish_response_notification(response_notice))
            except Exception:
                logger.exception("재수락 완료, 주보호자 알림 발행 확인 필요")

        # 거절 처리가 DB에 확정된 후 알림을 발행한다.
        if not data.accepted:
            try:
                recruitment_notification_published = (
                    publish_recruitment_notification(
                        schedule_seq,
                        answer_history_seq,
                    )
                )

                if not recruitment_notification_published:
                    logger.warning(
                        "일정 %s 거절 이력 %s 재모집 알림 발행 확인 필요",
                        schedule_seq,
                        answer_history_seq,
                    )
            except Exception:
                # 이미 확정된 거절과 배정 해제는 유지한다.
                logger.exception(
                    "일정 %s 거절 완료, 재모집 알림 발행 재시도 필요",
                    schedule_seq,
                )

        return {
            "result": "OK",
            "schedule_seq": schedule_seq,
            "response_notification_published": response_published,
            "request_history_seq": pending_request["request_history_seq"],
            "history_seq": answer_history_seq,
            "accepted": data.accepted,
            "recruitment_required": not data.accepted,
            "recruitment_notification_published": (
                recruitment_notification_published
            ),
        }

    except HTTPException:
        if conn is not None:
            conn.rollback()
        raise

    except (MySQLError, ValueError):
        if conn is not None:
            conn.rollback()

        raise HTTPException(
            503,
            "재수락 요청을 처리하지 못했습니다.",
        ) from None

    finally:
        if conn is not None:
            conn.close()
# 현재 주보호자가 일정을 삭제하고 전체 가족 알림을 준비한다.
@router.delete("/{schedule_seq}")
def delete_schedule(
    schedule_seq: int = Path(gt=0),
    family_room_id: str = Query(min_length=1, max_length=50),
    current_user_id: str = Depends(get_current_user_id),
) -> dict:
    conn = None
    changed = False
    history_seq = None

    try:
        conn = connect()

        check_representative(
            conn,
            family_room_id,
            current_user_id,
        )

        schedule = get_schedule_for_delete(
            conn,
            schedule_seq,
            family_room_id,
        )

        if schedule["deleted_at"] is not None:
            # 재요청이면 이력을 추가하지 않는다.
            history_seq = schedule["history_seq"]
            conn.rollback()

        else:
            deleted = mark_schedule_deleted(
                conn,
                schedule,
                current_user_id,
            )

            if deleted is None:
                raise HTTPException(
                    409,
                    "일정 상태가 변경됐습니다. 다시 조회해 주세요.",
                )

            history_seq = deleted["history_seq"]

            try:
                prepare_schedule_delete_notification(
                    conn,
                    deleted,
                )
            except Exception:
                logger.exception(
                    "일정 %s 삭제 알림 준비 실패",
                    schedule_seq,
                )
                raise HTTPException(
                    503,
                    "삭제 알림을 준비하지 못해 삭제 처리를 취소했습니다.",
                ) from None

            conn.commit()
            changed = True

    except HTTPException:
        if conn is not None:
            conn.rollback()
        raise

    except (MySQLError, ValueError):
        if conn is not None:
            conn.rollback()

        logger.exception("일정 %s 삭제 실패", schedule_seq)

        raise HTTPException(
            503,
            "일정을 삭제하지 못했습니다. 다시 시도해 주세요.",
        ) from None

    finally:
        if conn is not None:
            conn.close()

    # 삭제가 확정된 뒤 알림을 발행한다.
    notification_published = False

    if history_seq is not None:
        try:
            notification_published = publish_schedule_delete_notification(
                schedule_seq,
                history_seq,
            )
        except Exception:
            logger.exception(
                "일정 %s 삭제 완료, 삭제 알림 발행 재시도 필요",
                schedule_seq,
            )

        if not notification_published:
            logger.warning(
                "일정 %s 삭제 알림 발행 확인 필요",
                schedule_seq,
            )

    return {
        "result": "OK",
        "schedule_seq": schedule_seq,
        "history_seq": history_seq,
        "deleted": True,
        "changed": changed,
        "notification_published": notification_published,
    }
# 일정 관련 알림 API를 연결한다.
router.include_router(schedule_notifications_router)