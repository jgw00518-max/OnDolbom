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


def notification_count(connection, user_id):
    count, before = 0, None
    while True:
        events = list_notification_events(user_id, before, 100)
        for event in events:
            row = _visible(connection, user_id, event)
            if row is not None and row['read_at'] is None:
                count += 1
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
            result = {}
            # 한 기능의 Firestore 장애가 다른 메뉴의 정상적인 배지를 지우지 않도록 분리한다.
            for key, action in {
                'invites': lambda: invite_count(connection, user_id),
                'notifications': lambda: notification_count(connection, user_id),
                'notices': lambda: notice_count(connection, claims['uid']),
                'inquiries': lambda: inquiry_count(connection, user_id, claims['uid']),
            }.items():
                try:
                    result[key] = action()
                except (MySQLError, GoogleAPICallError, ValueError):
                    result[key] = None
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
