"""24시간 이하 긴급 재수락의 전화 안내를 한 번 처리한다."""

from datetime import datetime, time

from python.features.schedules.reconfirm_history import (
    get_pending_reconfirm_request,
)
from python.features.schedules.reconfirm_policy import get_reconfirm_deadline

from python.features.schedules.change_notifications import prepare_change

from python.database import connect
from python.features.notifications.store import get_event, publish

# 호출한 코드가 같은 연결에서 처리 완료 후 commit 또는 rollback한다.
def get_urgent_unverified_request(
    conn,
    schedule_seq: int,
    family_room_id: str,
):
    with conn.cursor() as cursor:
        # 변경·응답 처리와 같은 순서로 공간부터 잠근다.
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
            SELECT accepted_by, schedule_state, created_at
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

        current = request["current"]

        cursor.execute("SELECT CURRENT_TIMESTAMP AS server_now")
        server_now = cursor.fetchone()["server_now"]
        deadline = get_reconfirm_deadline(
            requested_at=request["requested_at"],
            schedule_date=current["schedule_date"],
            start_time=current["start_time"], now=server_now,
        )
        starts_at = datetime.combine(current["schedule_date"],
                                    time.fromisoformat(current["start_time"]))
        # 시작 후에는 새 전화 안내를 발송하지 않는다.
        if not deadline["is_urgent"] or server_now >= starts_at:
            return None

    return {
        "schedule_seq": schedule_seq,
        "family_room_id": family_room_id,
        "accepted_by": schedule["accepted_by"],
        "schedule_created_at": str(schedule["created_at"]),
        "request": request,
        "starts_at": starts_at,
        "server_now": server_now,
    }

# 같은 긴급 재수락 요청에는 주보호자 전화 알림을 하나만 준비한다.
def prepare_urgent_reconfirm_notification(conn, unverified: dict):
    with conn.cursor() as cursor:
        cursor.execute(
            """
            SELECT DISTINCT p.user_id
            FROM participate AS p
            JOIN `user` AS u ON u.user_id = p.user_id
            WHERE p.family_room_id = %s
              AND p.is_representative = 1
              AND p.left_at IS NULL
              AND u.withdrawn_at IS NULL
            """,
            (unverified["family_room_id"],),
        )
        recipients = sorted(
            row["user_id"] for row in cursor.fetchall()
        )

    if not recipients:
        raise ValueError(
            "긴급 재수락 전화 안내를 받을 주보호자가 없습니다."
        )

    request = unverified["request"]

    # 최신 메모 이력이 아니라 최초 요청 번호로 알림을 구분한다.
    return prepare_change({
        "notification_type": "schedule_reconfirm_urgent",
        "schedule_seq": unverified["schedule_seq"],
        "history_seq": request["request_history_seq"],
        "family_room_id": unverified["family_room_id"],
        "schedule_created_at": unverified["schedule_created_at"],
        "history_updated_at": str(request["requested_at"]),
        "request_history_seq": request["request_history_seq"],
        "requested_user_id": unverified["accepted_by"],
        "schedule_start_at": str(unverified["starts_at"]),
        "processed_by": "system",
        "reason": "urgent_reconfirm_phone",
        "recipient_ids": recipients,
        "message": "일정 시작까지 24시간 이하입니다. 기존 담당 가족에게 전화로 변경 내용을 확인해 주세요.",
    })

# 발행 직전에도 같은 긴급 요청이 아직 미응답인지 확인한다.
def publish_urgent_reconfirm_notification(identifier: str):
    event = get_event(identifier)

    if (
        event is None
        or event.get("status") not in ("pending", "published")
        or event.get("notification_type")
        != "schedule_reconfirm_urgent"
    ):
        return False

    conn = connect()

    try:
        unverified = get_urgent_unverified_request(
            conn,
            event["schedule_seq"],
            event["family_room_id"],
        )

        if unverified is None:
            return False

        request = unverified["request"]

        expected_id = (
            f"schedule_reconfirm_urgent_"
            f"{unverified['schedule_seq']}_"
            f"{request['request_history_seq']}"
        )

        if identifier != expected_id:
            return False

        expected = {
            "notification_id": identifier,
            "history_seq": request["request_history_seq"],
            "request_history_seq": request["request_history_seq"],
            "schedule_created_at": unverified["schedule_created_at"],
            "history_updated_at": str(request["requested_at"]),
            "requested_user_id": unverified["accepted_by"],
            "schedule_start_at": str(unverified["starts_at"]),
            "processed_by": "system",
            "reason": "urgent_reconfirm_phone",
        }

        if any(
            event.get(key) != value
            for key, value in expected.items()
        ):
            return False

        if not event.get("recipient_ids"):
            return False

        # 확인하는 동안 일정 변경·응답과 충돌하지 않도록 잠금을 유지한다.
        return publish(
            identifier,
            unverified["schedule_created_at"],
        )

    finally:
        # 조회 잠금을 해제한다. 담당 배정은 변경하지 않는다.
        try:
            conn.rollback()
        finally:
            conn.close()

# 긴급 전화 알림을 처리한다. 담당 배정은 유지한다.
def process_urgent_reconfirm_notice(
    schedule_seq: int,
    family_room_id: str,
):
    conn = connect()

    try:
        unverified = get_urgent_unverified_request(
            conn,
            schedule_seq,
            family_room_id,
        )

        if unverified is None:
            conn.rollback()
            return {
                "notified": False,
                "schedule_seq": schedule_seq,
            }

        identifier = prepare_urgent_reconfirm_notification(
            conn,
            unverified,
        )
        conn.commit()

    except Exception:
        conn.rollback()
        raise

    finally:
        conn.close()

    # 이미 발행한 알림은 반복해서 보내지 않는다.
    event = get_event(identifier)

    if event is not None and event.get("status") == "published":
        return {
            "notified": False,
            "already_published": True,
            "schedule_seq": schedule_seq,
            "notification_id": identifier,
        }

    published = publish_urgent_reconfirm_notification(identifier)

    return {
        "notified": published,
        "already_published": False,
        "schedule_seq": schedule_seq,
        "notification_id": identifier,
    }