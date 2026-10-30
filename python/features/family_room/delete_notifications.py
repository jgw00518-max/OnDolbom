"""공간 삭제 당시 가족에게만 보이는 안내와 기존 푸시 큐를 연결한다."""
from hashlib import sha256

from fastapi import HTTPException
from firebase_admin import firestore

from python.database import connect
from python.features.notifications import store

KIND = 'family_room_deleted'


def notification_id(room_id, created_at, deleted_at):
    # 재요청은 같은 문서, 롤백 후 다른 삭제 시도는 별도 버전으로 구분한다.
    version = sha256(f'{room_id}|{created_at}|{deleted_at}'.encode()).hexdigest()
    return f'{KIND}_{version}'


def _prepare(transaction, ref, payload):
    saved = ref.get(transaction=transaction)
    if saved.exists:
        old = saved.to_dict()
        if any(old.get(key) != payload[key] for key in (
                'family_room_id', 'room_created_at', 'room_deleted_at')):
            raise ValueError('Space deletion identity mismatch')
        # 이 함수는 DB에서 아직 미삭제인 공간을 잠근 경우에만 호출된다.
        # 초 단위 시각이 같은 롤백 재시도라면 이전 pending의 수신자를 최신 확정 대상으로 교체한다.
        if old.get('status') == 'pending' and any(
                old.get(key) != payload[key] for key in ('actor_id', 'recipient_ids')):
            transaction.update(ref, {key: payload[key] for key in ('actor_id', 'recipient_ids')})
        return  # 발행 완료 문서·읽음·푸시 상태는 보존한다.
    transaction.create(ref, {**payload, 'status': 'pending',
                             'created_at': firestore.SERVER_TIMESTAMP})


def prepare_notification(connection, room_id, room, deleted_at, actor_id):
    # 공간 잠금을 가진 삭제 트랜잭션에서 현재 활성 가족만 확정한다.
    with connection.cursor() as cursor:
        cursor.execute('''SELECT DISTINCT p.user_id FROM participate p
            JOIN `user` u ON u.user_id=p.user_id
            WHERE p.family_room_id=%s AND p.is_active=1 AND p.left_at IS NULL
              AND u.withdrawn_at IS NULL AND p.user_id<>%s''', (room_id, actor_id))
        recipients = [row['user_id'] for row in cursor.fetchall()]
    identifier = notification_id(room_id, room['created_at'], deleted_at)
    payload = dict(notification_id=identifier, notification_type=KIND,
                   family_room_id=room_id, room_created_at=str(room['created_at']),
                   room_deleted_at=str(deleted_at), care_recipient_name=room['care_recipient_name'],
                   actor_id=actor_id, recipient_ids=recipients)
    try:
        ref = store.collection().document(identifier)
        firestore.transactional(_prepare)(ref._client.transaction(), ref, payload)
    except Exception:
        # 준비 실패는 호출자의 MySQL 삭제도 rollback하도록 전달한다.
        raise HTTPException(503, '공간 삭제 알림을 준비하지 못했습니다. 다시 시도해 주세요.') from None
    return identifier


def deleted_room(connection, event):
    required = ('family_room_id', 'room_created_at', 'room_deleted_at')
    if event.get('notification_type') != KIND or any(not event.get(key) for key in required):
        return None
    if event.get('notification_id') != notification_id(*(event[key] for key in required)):
        return None
    with connection.cursor() as cursor:
        cursor.execute('''SELECT family_room_id, care_recipient_name, created_at,
            family_room_deleted_at FROM family_room WHERE family_room_id=%s''',
                       (event['family_room_id'],))
        room = cursor.fetchone()
    if (room is None or room['family_room_deleted_at'] is None
            or str(room['created_at']) != event['room_created_at']
            or str(room['family_room_deleted_at']) != event['room_deleted_at']
            or room['care_recipient_name'] != event.get('care_recipient_name')):
        return None
    return room


def _publish(transaction, ref, expected):
    saved = ref.get(transaction=transaction)
    event = saved.to_dict() if saved.exists else {}
    if any(event.get(key) != expected.get(key) for key in (
            'notification_id', 'room_created_at', 'room_deleted_at', 'recipient_ids')):
        return False
    if event.get('status') == 'pending':
        transaction.update(ref, dict(status='published', published_at=firestore.SERVER_TIMESTAMP,
                                     push_pending=bool(event.get('recipient_ids'))))
    return event.get('status') in {'pending', 'published'}


def publish_notification(identifier):
    event = store.get_event(identifier)
    if not event or event.get('notification_id') != identifier:
        return False
    connection = connect()
    try:
        # 롤백되거나 미확정인 삭제는 worker에서도 발행하지 않는다.
        if deleted_room(connection, event) is None:
            return False
        ref = store.collection().document(identifier)
        return firestore.transactional(_publish)(ref._client.transaction(), ref, event)
    finally:
        connection.close()


def visible_notification(connection, user_id, event):
    if (event.get('status') != 'published' or user_id not in event.get('recipient_ids', [])
            or user_id == event.get('actor_id')):
        return None
    room = deleted_room(connection, event)
    if room is None:
        return None
    with connection.cursor() as cursor:
        # 안내만 허용하며 삭제된 공간·일정·채팅의 접근 권한은 복원하지 않는다.
        cursor.execute('''SELECT p.participate_seq FROM participate p
            JOIN `user` u ON u.user_id=p.user_id
            WHERE p.family_room_id=%s AND p.user_id=%s AND p.is_active=1
              AND p.left_at IS NULL AND p.joined_at<=%s AND u.withdrawn_at IS NULL
            LIMIT 1''', (event['family_room_id'], user_id, room['family_room_deleted_at']))
        if cursor.fetchone() is None:
            return None
    receipt = store.inbox_state(event['notification_id'], user_id)
    if receipt.get('deleted_at'):
        return None
    return dict(notification_id=event['notification_id'], notification_type=KIND,
                family_room_id=event['family_room_id'], care_recipient_name=room['care_recipient_name'],
                room_deleted_at=event['room_deleted_at'], created_at=event['created_at'],
                read_at=receipt.get('read_at'))
