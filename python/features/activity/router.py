"""계정 메뉴 배지. 공유 MySQL은 조회만 하고 읽음 표시는 Firestore에 보관한다."""
from collections import defaultdict
from fastapi import APIRouter, Depends, HTTPException
from pydantic import BaseModel, ConfigDict, Field
from google.api_core.exceptions import GoogleAPICallError
from pymysql import MySQLError
from python.database import connect
from python.features.auth.firebase_auth import require_firebase_user
from python.features.inquiries.router import current_user, inquiry_detail
from python.features.notices.router import read_notices
from python.features.schedules.notification_router import visible_v2 as _visible
from python.features.notifications import store
from python.features.schedules.change_notifications import list_notification_events
from python.features.activity import receipts
from python.features.activity.cache import badge_cache

router = APIRouter(prefix='/activity', tags=['activity'])


def invite_count(connection, user_id):
    with connection.cursor() as cursor:
        # 만료 상태 갱신을 기다리지 않고 현재 시각으로 유효성을 판정한다.
        cursor.execute('''SELECT COUNT(*) AS count FROM invite i
            JOIN family_room f ON f.family_room_id=i.family_room_id
            JOIN `user` sender ON sender.user_id=i.inviter_id
            JOIN `user` recipient ON recipient.user_id=%s
            WHERE LOWER(TRIM(i.invite_email))=LOWER(TRIM(recipient.user_email))
            AND i.invite_status=%s AND i.invite_deleted_at IS NULL
            AND DATE_ADD(i.invite_at, INTERVAL 7 DAY)>CURRENT_TIMESTAMP
            AND f.family_room_deleted_at IS NULL AND sender.withdrawn_at IS NULL''', (user_id, '대기'))
        return cursor.fetchone()['count']


def notice_count(connection, uid):
    with connection.cursor() as cursor:
        cursor.execute('''SELECT admin_id, notice_id, notice_title, notice_content,
            notice_created_at, notice_updated_at FROM create_notice WHERE notice_deleted_at IS NULL''')
        items = {receipts.receipt_key('notice', [r['admin_id'], r['notice_id']]): receipts.notice_token(r)
                 for r in cursor.fetchall()}
    return receipts.unread_count(uid, items)


def inquiry_count(connection, user_id, uid):
    with connection.cursor() as cursor:
        # 한 문의에 새 답변이 여러 개 있어도 문의 배지는 한 개로 계산한다.
        cursor.execute('''SELECT a.question_seq, a.answer_seq, a.answer_content, a.answered_at
            FROM answer a JOIN question q ON q.question_seq=a.question_seq AND q.user_id=a.user_id
            WHERE q.user_id=%s AND q.question_deleted_at IS NULL AND a.answer_deleted_at IS NULL
            ORDER BY a.answer_seq''', (user_id,))
        groups = defaultdict(list)
        for row in cursor.fetchall():
            groups[row['question_seq']].append(row)
    return receipts.unread_count(uid, {receipts.receipt_key('inquiry', key): receipts.answer_token(rows)
                                      for key, rows in groups.items()})


def care_category(kind):
    if kind == 'memo_created':
        return 'memos'
    if kind == 'medication_created':
        return 'medications'
    if kind.startswith('schedule_'):
        return 'schedules'
    return None


def notification_count(connection, user_id, care_menu=None):
    count, before = 0, None
    while True:
        events = list_notification_events(user_id, before, 100)
        for event in events:
            row = _visible(connection, user_id, event)
            if row is not None and row['read_at'] is None:
                count += 1
                if care_menu is not None:
                    category = care_category(row.get('notification_type', event.get('notification_type', 'schedule_created')))
                    room_id = row.get('family_room_id', event.get('family_room_id'))
                    if category and room_id:
                        care_menu.setdefault(room_id, {}).setdefault(category, []).append(str(row.get('notification_id', event.get('notification_id'))))
        if len(events) < 100:
            return count
        before = str(events[-1]['notification_id'])


@router.get('/badges')
def badges(claims: dict = Depends(require_firebase_user), force: bool = False):
    connection = None
    try:
        connection = connect()
        with connection.cursor() as cursor:
            user_id = current_user(cursor, claims)
        # 캐시를 반환할 때도 인증과 현재 사용자 확인은 매번 수행한다.
        def calculate():
            result, care_menu = {}, {}
            # 한 기능의 Firestore 장애가 다른 메뉴의 정상적인 배지를 지우지 않도록 분리한다.
            for key, action in {
                'invites': lambda: invite_count(connection, user_id),
                'notifications': lambda: notification_count(connection, user_id, care_menu),
                'notices': lambda: notice_count(connection, claims['uid']),
                'inquiries': lambda: inquiry_count(connection, user_id, claims['uid']),
            }.items():
                try:
                    result[key] = action()
                except (MySQLError, GoogleAPICallError, ValueError):
                    result[key] = None
            # 같은 순회에서 공간별 미읽음 ID도 계산해 별도 Firestore 전체 조회를 하지 않는다.
            result['care_menu'] = care_menu if result['notifications'] is not None else None
            return result
        return badge_cache.load(claims['uid'], calculate, force=force)

    except (MySQLError, GoogleAPICallError, ValueError):
        raise HTTPException(503, '새 소식을 확인하지 못했습니다.') from None
    finally:
        if connection is not None:
            connection.close()


class ReadReceipt(BaseModel):
    model_config = ConfigDict(extra='forbid')
    token: str = Field(pattern=r'^[a-f0-9]{64}$')


def save_receipt(claims, kind, identity, token):
    try:
        receipts.mark_read(claims['uid'], receipts.receipt_key(kind, identity), token)
        badge_cache.invalidate(claims['uid'])
        return {'read': True}
    except (GoogleAPICallError, ValueError):
        raise HTTPException(503, '읽음 상태를 저장하지 못했습니다.') from None


@router.post('/notices/{admin_id}/{notice_id}/read')
def read_notice(admin_id: str, notice_id: str, payload: ReadReceipt,
                claims: dict = Depends(require_firebase_user)):
    row = read_notices(admin_id, notice_id)
    if payload.token != receipts.notice_token(row):
        raise HTTPException(409, '공지 내용이 변경되었습니다. 다시 확인해 주세요.')
    return save_receipt(claims, 'notice', [admin_id, notice_id], payload.token)


@router.post('/inquiries/{question_seq}/read')
def read_inquiry(question_seq: int, payload: ReadReceipt,
                 claims: dict = Depends(require_firebase_user)):
    row = inquiry_detail(question_seq=question_seq, claims=claims)
    if not row['answers'] or payload.token != receipts.answer_token(row['answers']):
        raise HTTPException(409, '답변 내용이 변경되었습니다. 다시 확인해 주세요.')
    return save_receipt(claims, 'inquiry', question_seq, payload.token)


class CareMenuReceipt(BaseModel):
    model_config = ConfigDict(extra='forbid')
    notification_ids: list[str] = Field(min_length=1, max_length=400)


@router.post('/spaces/{room_id}/{category}/read')
def read_care_menu(room_id: str, category: str, payload: CareMenuReceipt,
                   claims: dict = Depends(require_firebase_user)):
    if category not in {'memos', 'medications', 'schedules'}:
        raise HTTPException(404, '이용할 수 없는 돌봄 메뉴입니다.')
    connection = None
    try:
        connection = connect()
        with connection.cursor() as cursor:
            user_id = current_user(cursor, claims)
        identifiers = []
        # 메뉴에 진입할 때 확인한 ID만 읽는다. 로딩 중 새로 도착한 알림은 읽지 않는다.
        for identifier in dict.fromkeys(payload.notification_ids):
            if len(identifier) > 200 or not all(ch.isascii() and (ch.isalnum() or ch in '_-') for ch in identifier):
                raise HTTPException(422, '알림 식별자를 확인해 주세요.')
            event = store.get_event(identifier)
            if (not event or event.get('family_room_id') != room_id
                    or care_category(event.get('notification_type', 'schedule_created')) != category):
                continue
            row = _visible(connection, user_id, event)
            if row is not None and not row.get('read_at'):
                identifiers.append(identifier)
        store.mark_many_read(identifiers, user_id)
        return {'count': len(identifiers)}
    except (MySQLError, GoogleAPICallError, ValueError):
        raise HTTPException(503, '읽음 상태를 저장하지 못했습니다.') from None
    finally:
        badge_cache.invalidate(claims['uid'])
        if connection is not None:
            connection.close()
