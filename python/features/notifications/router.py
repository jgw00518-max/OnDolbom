"""Firestore 알림 목록·읽음 API. 현재 공간 접근 권한은 MySQL에서 재검사한다."""
from fastapi import APIRouter, Depends, HTTPException, Query, Path
from google.api_core.exceptions import GoogleAPICallError
from pymysql import MySQLError
from python.database import connect
from python.features.auth.firebase_auth import require_firebase_user
from python.features.notifications import store

router = APIRouter()


def _user_id(connection, claims):
    with connection.cursor() as cursor:
        cursor.execute('''SELECT user_id FROM `user` WHERE user_firebase_uid = %s
            AND BINARY user_firebase_uid = BINARY %s AND withdrawn_at IS NULL LIMIT 1''',
                       (claims['uid'], claims['uid']))
        row = cursor.fetchone()
    if row is None:
        raise HTTPException(403, '등록된 가족 사용자만 이용할 수 있습니다.')
    return row['user_id']


def _visible(connection, user_id, event):
    if not event or event.get('status') != 'published' or user_id not in event.get('recipient_ids', []):
        return None
    with connection.cursor() as cursor:
        cursor.execute('''SELECT s.schedule_seq, s.family_room_id, f.care_recipient_name,
            s.schedule_name, s.schedule_date, CAST(s.start_time AS CHAR) AS start_time,
            CAST(s.end_time AS CHAR) AS end_time, s.schedule_memo, s.created_at
            FROM create_schedule s JOIN family_room f ON f.family_room_id = s.family_room_id
            WHERE s.schedule_seq = %s AND s.family_room_id = %s AND s.deleted_at IS NULL
            AND f.family_room_deleted_at IS NULL AND EXISTS (SELECT 1 FROM participate p
                WHERE p.family_room_id = s.family_room_id AND p.user_id = %s AND p.left_at IS NULL)''',
                       (event['schedule_seq'], event['family_room_id'], user_id))
        row = cursor.fetchone()
    if row is None or str(row['created_at']) != event['schedule_created_at']:
        return None
    return {**row, 'notification_id': event['schedule_seq'], 'created_at': event['created_at'],
            'read_at': store.read_at(event['schedule_seq'], user_id)}


def _run(claims, action):
    connection = None
    try:
        connection = connect()
        return action(connection, _user_id(connection, claims))
    except (MySQLError, GoogleAPICallError, ValueError):
        raise HTTPException(503, 'Firestore 설정·색인 및 서버 연결을 확인해 주세요.') from None
    finally:
        if connection is not None:
            connection.close()


@router.get('')
def list_notifications(before_id: int | None = Query(default=None, gt=0),
                       limit: int = Query(default=30, ge=1, le=100),
                       claims: dict = Depends(require_firebase_user)):
    def action(connection, user_id):
        events = store.list_events(user_id, before_id, limit + 1)
        scanned = events[:limit]
        rows = [row for event in scanned if (row := _visible(connection, user_id, event)) is not None]
        # 권한 때문에 숨긴 항목도 커서를 전진시켜 다음 페이지를 조회할 수 있게 한다.
        return dict(results=rows, next_before_id=scanned[-1]['schedule_seq'] if len(events) > limit else None)
    return _run(claims, action)


def _required(connection, user_id, identifier):
    row = _visible(connection, user_id, store.get_event(identifier))
    if row is None:
        raise HTTPException(404, '알림이 없거나 현재 접근할 수 없습니다.')
    return row


@router.get('/{notification_id}/schedule')
def notification_schedule(notification_id: int = Path(gt=0), claims: dict = Depends(require_firebase_user)):
    return _run(claims, lambda connection, user_id: _required(connection, user_id, notification_id))


@router.post('/{notification_id}/read')
def read_notification(notification_id: int = Path(gt=0), claims: dict = Depends(require_firebase_user)):
    def action(connection, user_id):
        _required(connection, user_id, notification_id)
        return dict(notification_id=notification_id, read_at=store.mark_read(notification_id, user_id))
    return _run(claims, action)
