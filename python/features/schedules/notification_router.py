from python.features.activity.cache import badge_cache
from python.features.schedules.reminders import reminder_is_current
"""일정 담당 B의 알림 조회 API. A의 공통 저장 함수를 재사용한다."""
from typing import Literal
from fastapi import APIRouter, Depends, HTTPException, Query, Path
from google.api_core.exceptions import GoogleAPICallError
from pymysql import MySQLError
from python.database import connect
from python.features.auth.firebase_auth import require_firebase_user
from python.features.notifications import store
from python.features.schedules.change_notifications import list_notification_events
import logging

logger = logging.getLogger(__name__)

router = APIRouter(prefix="/schedule-notifications", tags=["schedule-notifications"])


def _user_id(connection, claims):
    with connection.cursor() as cursor:
        cursor.execute('''SELECT user_id FROM `user` WHERE user_firebase_uid = %s
            AND BINARY user_firebase_uid = BINARY %s AND withdrawn_at IS NULL LIMIT 1''',
                       (claims['uid'], claims['uid']))
        row = cursor.fetchone()
    if row is None:
        raise HTTPException(403, '등록된 가족 사용자만 이용할 수 있습니다.')
    return row['user_id']


# 삭제 안내는 현재 참여 가족에게만 보이고 삭제 당시 내용으로 검증한다.
def _visible_deleted(connection, user_id, event):
    identifier = (
        f"schedule_deleted_{event['schedule_seq']}_{event.get('history_seq')}"
    )
    if event.get('notification_id') != identifier:
        return None

    with connection.cursor() as cursor:
        cursor.execute(
            """
            SELECT s.schedule_seq, s.family_room_id, s.created_at,
                s.deleted_at, f.care_recipient_name,
                h.history_seq, h.updated_at AS history_updated_at,
                h.changed_by, h.schedule_date,
                h.updated_schedule_name AS schedule_name,
                CAST(h.updated_start_time AS CHAR) AS start_time,
                CAST(h.updated_end_time AS CHAR) AS end_time,
                h.updated_schedule_memo AS schedule_memo
            FROM create_schedule AS s
            JOIN family_room AS f ON f.family_room_id = s.family_room_id
            JOIN update_schedule AS h
              ON h.schedule_seq = s.schedule_seq
             AND h.family_room_id = s.family_room_id
            WHERE s.schedule_seq = %s AND s.family_room_id = %s
              AND h.history_seq = %s
              AND s.deleted_at IS NOT NULL
              AND s.accepted_by IS NULL
              AND h.update_accepted_by IS NULL
              AND h.update_accepted_at IS NULL
              AND f.family_room_deleted_at IS NULL
              AND h.history_seq = (
                  SELECT MAX(h2.history_seq) FROM update_schedule AS h2
                  WHERE h2.schedule_seq = s.schedule_seq
                    AND h2.family_room_id = s.family_room_id
              )
              AND EXISTS (
                  SELECT 1 FROM participate AS p
                  JOIN `user` AS u ON u.user_id = p.user_id
                  WHERE p.family_room_id = s.family_room_id
                    AND p.user_id = %s
                    AND p.left_at IS NULL AND u.withdrawn_at IS NULL
              )
            LIMIT 1
            """,
            (event['schedule_seq'], event['family_room_id'],
             event.get('history_seq'), user_id),
        )
        saved = cursor.fetchone()

    if saved is None:
        return None

    expected = {
        'schedule_created_at': str(saved['created_at']),
        'history_updated_at': str(saved['history_updated_at']),
        'deleted_at': str(saved['deleted_at']),
        'deleted_by': saved['changed_by'],
        'schedule_name': saved['schedule_name'],
        'schedule_date': str(saved['schedule_date']),
        'start_time': saved['start_time'],
        'end_time': saved['end_time'],
        'schedule_memo': saved['schedule_memo'],
    }
    if any(event.get(key) != value for key, value in expected.items()):
        return None

    details = {key: saved[key] for key in (
        'schedule_seq', 'family_room_id', 'care_recipient_name',
        'schedule_name', 'schedule_date', 'start_time', 'end_time',
        'schedule_memo', 'history_seq',
    )}
    return {
        **details,
        'notification_id': identifier,
        'notification_type': 'schedule_deleted',
        'deleted': True,
        'deleted_at': str(saved['deleted_at']),
        'created_at': event['created_at'],
        'read_at': store.read_at(identifier, user_id),
    }


def _visible(connection, user_id, event):
    if not event or event.get('status') != 'published' or user_id not in event.get('recipient_ids', []):
        return None
    if event.get('notification_type') == 'schedule_reminder' and not reminder_is_current(connection, event):
        return None
    if event.get('notification_type') == 'schedule_deleted':
        return _visible_deleted(connection, user_id, event)
    with connection.cursor() as cursor:
        cursor.execute('''SELECT s.schedule_seq, s.family_room_id, f.care_recipient_name,
            CASE WHEN h.history_seq IS NULL THEN s.schedule_name ELSE h.updated_schedule_name END AS schedule_name,
            CASE WHEN h.history_seq IS NULL THEN s.schedule_date ELSE h.schedule_date END AS schedule_date,
            CAST(CASE WHEN h.history_seq IS NULL THEN s.start_time ELSE h.updated_start_time END AS CHAR) AS start_time,
            CAST(CASE WHEN h.history_seq IS NULL THEN s.end_time ELSE h.updated_end_time END AS CHAR) AS end_time,
            CASE WHEN h.history_seq IS NULL THEN s.schedule_memo ELSE h.updated_schedule_memo END AS schedule_memo,
            s.created_at
            FROM create_schedule s JOIN family_room f ON f.family_room_id = s.family_room_id
            LEFT JOIN update_schedule h ON h.schedule_seq = s.schedule_seq
              AND h.family_room_id = s.family_room_id
              AND h.history_seq = (SELECT MAX(h2.history_seq) FROM update_schedule h2
                  WHERE h2.schedule_seq = s.schedule_seq)
            WHERE s.schedule_seq = %s AND s.family_room_id = %s AND s.deleted_at IS NULL
            AND f.family_room_deleted_at IS NULL AND EXISTS (SELECT 1 FROM participate p
                WHERE p.family_room_id = s.family_room_id AND p.user_id = %s AND p.left_at IS NULL)''',
                       (event['schedule_seq'], event['family_room_id'], user_id))
        row = cursor.fetchone()
    if row is None or str(row['created_at']) != event['schedule_created_at']:
        return None
    kind = event.get('notification_type', 'schedule_created')
    # 한 재모집 이벤트라도 현재 역할에 맞는 안내를 반환한다.
    if kind == 'schedule_recruitment' and event.get('request_history_seq') is None:
        with connection.cursor() as cursor:
            cursor.execute('SELECT is_representative FROM participate WHERE family_room_id=%s AND user_id=%s AND left_at IS NULL', (event['family_room_id'], user_id))
            member = cursor.fetchone()
        if member and member['is_representative'] == 1:
            kind = 'schedule_declined'
    identifier = event.get('notification_id', event['schedule_seq'])
    return {**row, 'notification_id': str(identifier),
            'notification_type': kind,
            'actor_name': event.get('actor_name'),
            'history_seq': event.get('history_seq'),
            'created_at': event['created_at'],
            'read_at': store.read_at(identifier, user_id)}


def visible_v2(connection, user_id, event):
    """V2 알림함과 배지가 동일한 유형·권한 기준을 사용한다."""
    kind = event.get('notification_type', 'schedule_created')
    if kind not in {'schedule_created', 'schedule_changed', 'schedule_reconfirm', 'schedule_recruitment', 'schedule_accepted', 'schedule_reconfirmed', 'schedule_deleted', 'schedule_reminder'}:
        return None
    # 자동 만료에 따른 재모집은 V2의 거절 후 재모집과 구분한다.
    if kind == 'schedule_recruitment' and event.get('request_history_seq') is not None:
        return None
    return _visible(connection, user_id, event)


def _run(claims, action):
    connection = None
    try:
        connection = connect()
        return action(connection, _user_id(connection, claims))
    except (MySQLError, GoogleAPICallError, ValueError):
        logger.exception("일정 알림 조회·처리 실패")
        raise HTTPException(
            503,
            'Firestore 설정·색인 및 서버 연결을 확인해 주세요.',
        ) from None
    finally:
        if connection is not None:
            connection.close()


@router.get('')
def list_notifications(scope: Literal["all", "v2"] = Query(default="all"), before_id: str | None = Query(default=None, min_length=1, max_length=200),
                       limit: int = Query(default=30, ge=1, le=100),
                       claims: dict = Depends(require_firebase_user)):
    def action(connection, user_id):
        events = list_notification_events(user_id, before_id, limit + 1)
        scanned = events[:limit]
        visible = visible_v2 if scope == 'v2' else _visible
        rows = [row for event in scanned if (row := visible(connection, user_id, event)) is not None]
        # 권한 때문에 숨긴 항목도 커서를 전진시켜 다음 페이지를 조회할 수 있게 한다.
        return dict(results=rows, next_before_id=str(scanned[-1]['notification_id']) if len(events) > limit else None)
    return _run(claims, action)


def _required(connection, user_id, identifier):
    row = _visible(connection, user_id, store.get_event(identifier))
    if row is None:
        raise HTTPException(404, '알림이 없거나 현재 접근할 수 없습니다.')
    return row


@router.get('/{notification_id}/schedule')
def notification_schedule(notification_id: str = Path(min_length=1, max_length=200, pattern=r"^[A-Za-z0-9_-]+$"), claims: dict = Depends(require_firebase_user)):
    def action(connection, user_id):
        notification = _required(connection, user_id, notification_id)
        if notification.get('notification_type') == 'schedule_deleted':
            raise HTTPException(410, '삭제된 일정입니다.')
        return notification
    return _run(claims, action)


@router.post('/{notification_id}/read')
def read_notification(notification_id: str = Path(min_length=1, max_length=200, pattern=r"^[A-Za-z0-9_-]+$"), claims: dict = Depends(require_firebase_user)):
    def action(connection, user_id):
        _required(connection, user_id, notification_id)
        read_at = store.mark_read(notification_id, user_id)
        # 읽음 저장이 성공한 후에만 현재 계정의 배지 캐시를 폐기한다.
        badge_cache.invalidate(claims['uid'])
        return dict(notification_id=notification_id, read_at=read_at)
    return _run(claims, action)
