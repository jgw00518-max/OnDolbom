"""일반 재수락 요청의 응답 기한 만료를 확인한다."""

from python.features.schedules.reconfirm_history import (
    get_pending_reconfirm_request,
)
from python.features.schedules.reconfirm_policy import get_reconfirm_deadline

import logging
from datetime import datetime, time

from python.database import connect
from python.features.schedules.change_notifications import (
    prepare_reconfirm_expiry_notifications,
    publish_reconfirm_expiry_notification,
    prepare_recruitment_notification,
    publish_recruitment_notification,
)

logger = logging.getLogger(__name__)


# 호출한 코드가 같은 연결에서 처리 완료 후 commit 또는 rollback한다.
def get_expired_reconfirm_request(
    conn,
    schedule_seq: int,
    family_room_id: str,
):
    with conn.cursor() as cursor:
        # 다른 변경·응답 처리와 같은 순서로 공간부터 잠근다.
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
            return None

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

        if (
            schedule is None
            or schedule["schedule_state"] != "미완료"
            or schedule["accepted_by"] is None
        ):
            return None

        request = get_pending_reconfirm_request(
            conn,
            schedule_seq,
            family_room_id,
            schedule["accepted_by"],
        )

        if request is None:
            return None

        deadline = get_reconfirm_deadline(
            requested_at=request["requested_at"],
            schedule_date=request["current"]["schedule_date"],
            start_time=request["current"]["start_time"],
        )

        # 긴급 변경은 자동 만료하지 않는다.
        if deadline["is_urgent"]:
            return None

        cursor.execute("SELECT CURRENT_TIMESTAMP AS server_now")
        server_now = cursor.fetchone()["server_now"]

        if server_now < deadline["response_due_at"]:
            return None

    return {
        "schedule_seq": schedule_seq,
        "family_room_id": family_room_id,
        "accepted_by": schedule["accepted_by"],
        "request": request,
        "response_due_at": deadline["response_due_at"],
        "server_now": server_now,
    }

# 알림 준비까지 성공한 뒤 호출한 코드에서 commit한다.
def release_expired_reconfirm_request(
    conn,
    schedule_seq: int,
    family_room_id: str,
):
    expired = get_expired_reconfirm_request(
        conn,
        schedule_seq,
        family_room_id,
    )

    if expired is None:
        return None

    current = expired["request"]["current"]

    with conn.cursor() as cursor:
        cursor.execute(
            """
            SELECT user_id
            FROM `user`
            WHERE user_id = 'system'
              AND user_firebase_uid IS NULL
              AND withdrawn_at IS NULL
            """
        )

        if cursor.fetchone() is None:
            raise ValueError("자동 처리용 system 등록을 확인해 주세요.")

        cursor.execute(
            """
            UPDATE create_schedule
            SET accepted_by = NULL
            WHERE schedule_seq = %s
              AND family_room_id = %s
              AND accepted_by = %s
              AND deleted_at IS NULL
              AND schedule_state = '미완료'
            """,
            (
                schedule_seq,
                family_room_id,
                expired["accepted_by"],
            ),
        )

        if cursor.rowcount != 1:
            raise ValueError(
                "담당 배정이 달라져 자동 만료를 중단했습니다."
            )

        # 이전 요청은 보존하고 자동 배정 해제 결과를 새 이력으로 남긴다.
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
                %s, %s, %s, 'system', NULL, NULL,
                %s, %s, %s, %s
            )
            """,
            (
                schedule_seq,
                current["schedule_date"],
                family_room_id,
                current["schedule_name"],
                current["start_time"],
                current["end_time"],
                current["schedule_memo"],
            ),
        )
        history_seq = cursor.lastrowid

    return {
        **expired,
        "history_seq": history_seq,
        "request_history_seq": (
            expired["request"]["request_history_seq"]
        ),
    }

# 한 일정의 자동 만료·이력 저장·알림 준비·발행을 연결한다.
def process_reconfirm_expiry(
    schedule_seq: int,
    family_room_id: str,
):
    conn = connect()

    try:
        expired = release_expired_reconfirm_request(
            conn,
            schedule_seq,
            family_room_id,
        )

        if expired is None:
            conn.rollback()
            return {
                "expired": False,
                "schedule_seq": schedule_seq,
            }

        # 배정 해제와 같은 연결에서 만료 안내를 준비한다.
        identifiers = prepare_reconfirm_expiry_notifications(
            conn,
            expired,
        )

        current = expired["request"]["current"]
        starts_at = datetime.combine(
            current["schedule_date"],
            time.fromisoformat(current["start_time"]),
        )
        recruitment_required = expired["server_now"] < starts_at

        # 시작 전이면 전체 가족 재모집 알림도 준비한다.
        if recruitment_required:
            prepare_recruitment_notification(
                conn,
                schedule_seq,
                expired["history_seq"],
            )

        conn.commit()

    except Exception:
        conn.rollback()
        raise

    finally:
        conn.close()

    # DB 저장이 확정된 뒤에만 알림을 발행한다.
    notification_results = {}

    for identifier in identifiers:
        try:
            published = publish_reconfirm_expiry_notification(
                identifier
            )
        except Exception:
            published = False
            logger.exception(
                "자동 만료 안내 발행 실패: %s",
                identifier,
            )

        notification_results[identifier] = published

        if not published:
            logger.warning(
                "자동 만료 안내 발행 재시도 필요: %s",
                identifier,
            )

    recruitment_published = False

    if recruitment_required:
        try:
            recruitment_published = publish_recruitment_notification(
                schedule_seq,
                expired["history_seq"],
            )
        except Exception:
            logger.exception(
                "일정 %s 자동 만료 후 재모집 알림 발행 실패",
                schedule_seq,
            )

        if not recruitment_published:
            logger.warning(
                "일정 %s 재모집 알림 발행 확인 필요",
                schedule_seq,
            )

    return {
        "expired": True,
        "schedule_seq": schedule_seq,
        "history_seq": expired["history_seq"],
        "request_history_seq": expired["request_history_seq"],
        "notification_results": notification_results,
        "recruitment_required": recruitment_required,
        "recruitment_notification_published": recruitment_published,
    }