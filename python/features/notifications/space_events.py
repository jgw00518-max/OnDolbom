"""공간·기록 알림: MySQL 확정 여부와 수신 권한을 검사하고 기존 수신함을 재사용한다."""
import logging
from uuid import uuid4
from firebase_admin import firestore
from google.api_core.exceptions import GoogleAPICallError
from fastapi import HTTPException
from python.database import connect
from python.features.notifications import store

TITLES = {
    'representative_transferred': '주보호자가 변경되었어요',
    'member_left': '가족이 돌봄 공간에서 나갔어요',
    'member_removed': '가족의 돌봄 공간 참여가 종료되었어요',
    'memo_created': '새 메모가 등록되었어요',
    'medication_created': '새 투약일지가 등록되었어요',
}
logger = logging.getLogger(__name__)


def prepare(connection, room_id, actor_id, kind, source_id, *, target_id=None):
    """업무 트랜잭션 안에서 준비한다. 만료·탈퇴 계정은 수신 대상에서 제외한다."""
    with connection.cursor() as cursor:
        cursor.execute("""SELECT DISTINCT p.user_id FROM participate p JOIN `user` u ON u.user_id=p.user_id
            WHERE p.family_room_id=%s AND u.withdrawn_at IS NULL
            AND (p.left_at IS NULL OR p.user_id=%s)""", (room_id, target_id))
        recipients = [r['user_id'] for r in cursor.fetchall()]
    if kind != 'member_left':
        recipients = [u for u in recipients if u != actor_id]
    identifier = 'space_' + uuid4().hex
    payload = dict(notification_id=identifier, notification_type=kind, family_room_id=room_id,
        actor_id=actor_id, target_id=target_id, source_id=str(source_id), recipient_ids=recipients,
        status='pending', created_at=firestore.SERVER_TIMESTAMP)
    # 먼저 pending으로 남겨 API 발행 실패는 기존 worker가 재시도할 수 있게 한다.
    try:
        store.collection().document(identifier).create(payload, timeout=10)
    except GoogleAPICallError:
        raise HTTPException(503, '알림 저장소에 연결하지 못했습니다. 다시 시도해 주세요.') from None
    return identifier


def committed(connection, event):
    """다른 연결에서 원본을 확인하므로 미확정·rollback된 작업은 발행하지 않는다."""
    kind, source, room = event['notification_type'], event['source_id'], event['family_room_id']
    with connection.cursor() as cursor:
        if kind == 'memo_created':
            cursor.execute('SELECT memo_id FROM memo WHERE memo_id=%s AND family_room_id=%s', (source, room))
        elif kind == 'medication_created':
            cursor.execute('SELECT medication_log_seq FROM medication_log WHERE medication_log_seq=%s AND family_room_id=%s', (source, room))
        elif kind in ('member_left', 'member_removed'):
            cursor.execute('SELECT participate_seq FROM participate WHERE participate_seq=%s AND family_room_id=%s AND left_at IS NOT NULL', (source, room))
        elif kind == 'representative_transferred':
            cursor.execute('SELECT participate_seq FROM participate WHERE participate_seq=%s AND family_room_id=%s AND user_id=%s AND is_representative=1 AND left_at IS NULL', (source, room, event['target_id']))
        else:
            return False
        return cursor.fetchone() is not None


def _publish_once(transaction, ref):
    # API와 worker의 동시 재시도가 이미 발송된 푸시를 다시 큐에 넣지 않게 한다.
    snapshot = ref.get(transaction=transaction, timeout=10)
    if not snapshot.exists:
        return False
    if snapshot.to_dict().get('status') == 'pending':
        transaction.update(ref, dict(status='published', push_pending=True))
    return True


def publish(identifier):
    connection = connect()
    try:
        event = store.get_event(identifier)
        if event and committed(connection, event):
            ref = store.collection().document(identifier)
            return firestore.transactional(_publish_once)(ref._client.transaction(), ref)
        return False
    finally:
        connection.close()


def publish_safely(identifier):
    # 업무 commit 이후 Firestore 장애로 성공한 저장을 실패처럼 응답하지 않는다.
    try:
        publish(identifier)
    except Exception:
        logger.warning('공간 알림 발행 보류; worker에서 재시도')


def visible(connection, user_id, event):
    """종료된 가족은 종료 사실만 확인할 수 있고 공간의 데이터는 조회하지 못한다."""
    with connection.cursor() as cursor:
        cursor.execute("""SELECT f.care_recipient_name FROM family_room f
            WHERE f.family_room_id=%s AND f.family_room_deleted_at IS NULL
            AND EXISTS (SELECT 1 FROM participate p WHERE p.family_room_id=f.family_room_id
                AND p.user_id=%s AND p.left_at IS NULL)""", (event['family_room_id'], user_id))
        room = cursor.fetchone()
    ended_target = event['notification_type'] in ('member_left', 'member_removed') and event.get('target_id') == user_id
    if room is None and not ended_target:
        return None
    receipt = store.inbox_state(event['notification_id'], user_id)
    if receipt.get('deleted_at'):
        return None
    return dict(notification_id=event['notification_id'], notification_type=event['notification_type'],
        family_room_id=event['family_room_id'], care_recipient_name=room['care_recipient_name'] if room else '돌봄 공간',
        schedule_seq=0, schedule_name=TITLES[event['notification_type']], schedule_date='',
        start_time='', end_time='', schedule_memo=None, created_at=event['created_at'], read_at=receipt.get('read_at'))
