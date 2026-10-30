from python.features.schedules.withdraw_schedule import publish_withdrawal_notification
"""실행 중 1분마다 재수락 만료를 확인한다."""

import logging
from time import monotonic, sleep

from google.cloud.firestore_v1.base_query import FieldFilter

from python.features.notifications.schedule_notifications import publish_schedule_notifications
from python.features.schedules.response_notifications import retry_response_notification
from python.database import connect
from python.features.notifications.store import collection
from python.features.schedules.change_notifications import (
    publish_reconfirm_expiry_notification,
    publish_reconfirm_notification,
    publish_schedule_change_notification,
    publish_recruitment_notification,
)
from python.features.schedules.reconfirm_expiry import process_reconfirm_expiry
from python.features.schedules.delete_schedule import (
    publish_schedule_delete_notification,
)

from python.features.schedules.urgent_reconfirm import (
    process_urgent_reconfirm_notice,
    publish_urgent_reconfirm_notification,
)


CHECK_INTERVAL_SECONDS = 60
logger = logging.getLogger(__name__)


# 현재 재수락 대기 중인 일정을 찾아 만료 여부를 확인한다.
def check_expired_requests():
    conn = connect()

    try:
        with conn.cursor() as cursor:
            cursor.execute(
                """
                SELECT s.schedule_seq, s.family_room_id
                FROM create_schedule AS s
                JOIN family_room AS f
                  ON f.family_room_id = s.family_room_id
                JOIN update_schedule AS h
                  ON h.schedule_seq = s.schedule_seq
                 AND h.family_room_id = s.family_room_id
                 AND h.history_seq = (
                     SELECT MAX(h2.history_seq)
                     FROM update_schedule AS h2
                     WHERE h2.schedule_seq = s.schedule_seq
                       AND h2.family_room_id = s.family_room_id
                 )
                WHERE s.deleted_at IS NULL
                  AND f.family_room_deleted_at IS NULL
                  AND s.schedule_state = '미완료'
                  AND s.accepted_by IS NOT NULL
                  AND h.update_accepted_by = s.accepted_by
                  AND h.update_accepted_at IS NULL
                ORDER BY s.schedule_seq
                """
            )
            schedules = cursor.fetchall()

    finally:
        conn.close()

    for schedule in schedules:
        try:
            # 잠금 후 현재 요청과 기한을 다시 검사한다.
            # 긴급 변경은 기존 만료 처리 함수에서 제외한다.
            result = process_reconfirm_expiry(
                schedule["schedule_seq"],
                schedule["family_room_id"],
            )

            if result["expired"]:
                logger.info(
                    "일정 %s 자동 만료 완료, 처리 이력 %s",
                    result["schedule_seq"],
                    result["history_seq"],
                )
            else:
                # 일반 만료 대상이 아니면 긴급 미확인 여부를 확인한다.
                notice_result = process_urgent_reconfirm_notice(
                    schedule["schedule_seq"],
                    schedule["family_room_id"],
                )

                if notice_result["notified"]:
                    logger.info(
                        "일정 %s 긴급 재수락 미확인 안내 완료",
                        schedule["schedule_seq"],
                    )

        except Exception:
            # 한 일정의 오류 때문에 다른 일정 확인을 중단하지 않는다.
            logger.exception(
                "일정 %s 만료 확인 실패",
                schedule["schedule_seq"],
            )


# 재모집 알림을 재시도하기 전에 일정 시작 전인지 확인한다.
def can_retry_recruitment(event):
    conn = connect()

    try:
        with conn.cursor() as cursor:
            cursor.execute(
                """
                SELECT
                    TIMESTAMP(schedule_date, updated_start_time)
                        > CURRENT_TIMESTAMP AS can_recruit
                FROM update_schedule
                WHERE schedule_seq = %s
                  AND history_seq = %s
                """,
                (
                    event["schedule_seq"],
                    event["history_seq"],
                ),
            )
            row = cursor.fetchone()

        return row is not None and bool(row["can_recruit"])

    finally:
        conn.close()


# DB 커밋 후 발행에 실패한 알림을 기존 검증·발행 함수를 통해 복구한다.
def retry_pending_notifications():
    snapshots = (
        collection()
        .where(filter=FieldFilter("status", "==", "pending"))
        .stream(timeout=10)
    )

    for snapshot in snapshots:
        event = snapshot.to_dict()
        notification_type = event.get("notification_type")

        try:
            from python.features.notifications import space_events
            if notification_type in space_events.TITLES:
                published = space_events.publish(snapshot.id)
            elif notification_type in (None, 'schedule_created'):
                # 기존 등록 문서는 notification_type이 없고 일정 번호를 문서 ID로 쓴다.
                if snapshot.id != str(event.get('schedule_seq')):
                    continue
                published = publish_schedule_notifications(event['schedule_seq'])
            elif notification_type in ('schedule_changed', 'schedule_reconfirm'):
                if snapshot.id != f"{notification_type}_{event.get('schedule_seq')}_{event.get('history_seq')}":
                    continue
                publisher = (publish_schedule_change_notification
                             if notification_type == 'schedule_changed'
                             else publish_reconfirm_notification)
                published = publisher(event['schedule_seq'], event['history_seq'])
            elif notification_type in ('schedule_accepted', 'schedule_reconfirmed'):
                published = retry_response_notification(snapshot.id)
            elif event.get('reason') == 'participation_withdrawal':
                if notification_type == 'schedule_recruitment' and not can_retry_recruitment(event):
                    continue
                published = publish_withdrawal_notification(snapshot.id)
            elif notification_type in (
                "schedule_reconfirm_expired",
                "schedule_reconfirm_unanswered",
            ):
                published = publish_reconfirm_expiry_notification(
                    snapshot.id
                )
            elif notification_type == "schedule_reconfirm_unverified":
                published = publish_urgent_reconfirm_notification(
                    snapshot.id
                )


            elif notification_type == "schedule_deleted":
                identifier = (
                    f"schedule_deleted_{event['schedule_seq']}_"
                    f"{event['history_seq']}"
                )
                if snapshot.id != identifier:
                    continue
                # 발행 직전에 삭제 이력과 현재 공간 상태를 다시 확인한다.
                published = publish_schedule_delete_notification(
                    event["schedule_seq"],
                    event["history_seq"],
                )

            elif notification_type == "schedule_recruitment":
                # 일정 시작 후에는 지난 재모집 알림을 다시 보내지 않는다.
                if not can_retry_recruitment(event):
                    continue

                published = publish_recruitment_notification(
                    event["schedule_seq"],
                    event["history_seq"],
                )

            else:
                continue

            if published:
                logger.info(
                    "알림 재발행 완료: %s",
                    snapshot.id,
                )

        except Exception:
            logger.exception(
                "알림 발행 재시도 실패: %s",
                snapshot.id,
            )


def main():
    logging.basicConfig(
        level=logging.INFO,
        format="%(asctime)s %(levelname)s %(message)s",
    )

    logger.info(
        "재수락 자동 만료 확인 시작: 1분 간격, 종료는 Ctrl+C"
    )

    try:
        while True:
            started_at = monotonic()

            try:
                check_expired_requests()
            except Exception:
                logger.exception("재수락 만료 대상 조회 실패")

            try:
                retry_pending_notifications()
            except Exception:
                logger.exception("미발행 알림 조회 실패")

            # 처리 시간을 제외한 나머지만 기다려 확인 주기를 맞춘다.
            elapsed = monotonic() - started_at
            sleep(max(0, CHECK_INTERVAL_SECONDS - elapsed))

    except KeyboardInterrupt:
        logger.info("재수락 자동 만료 확인을 종료했습니다.")


if __name__ == "__main__":
    main()