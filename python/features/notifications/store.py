"""Firestore 알림 저장. 클라이언트는 API를 통해서만 접근한다."""
from hashlib import sha256

from firebase_admin import firestore
from google.cloud.firestore_v1.base_query import FieldFilter
from python.features.auth.firebase_auth import get_firebase_app


PUSH_TYPES = frozenset({'family_room_deleted', 'schedule_created', 'schedule_changed', 'schedule_deleted', 'schedule_reconfirm',
                        'schedule_accepted', 'schedule_reconfirmed', 'schedule_recruitment', 'schedule_reminder', 'schedule_withdrawn',
                        'schedule_reconfirm_expired', 'schedule_reconfirm_unanswered', 'schedule_reconfirm_unverified'})


def supports_push(event):
    """자동 만료·긴급 미확인도 저장된 수신자 그대로 푸시에 연결한다."""
    return event.get('notification_type', 'schedule_created') in PUSH_TYPES


def collection():
    return firestore.client(app=get_firebase_app()).collection('schedule_notifications')


def _receipt(ref, user_id):
    return ref.collection('reads').document(sha256(user_id.encode()).hexdigest())


def get_event(identifier):
    snapshot = collection().document(str(identifier)).get(timeout=10)
    return snapshot.to_dict() if snapshot.exists else None


def list_events(user_id, before, limit):
    query = collection().where(filter=FieldFilter('status', '==', 'published')).where(
        filter=FieldFilter('recipient_ids', 'array_contains', user_id))
    if before is not None:
        query = query.where(filter=FieldFilter('schedule_seq', '<', before))
    return [snapshot.to_dict() for snapshot in query.order_by(
        'schedule_seq', direction=firestore.Query.DESCENDING).limit(limit).stream(timeout=10)]


def inbox_state(identifier, user_id):
    # 한 번의 문서 읽기로 읽음·개인 삭제 상태를 함께 가져온다.
    snapshot = _receipt(collection().document(str(identifier)), user_id).get(timeout=10)
    return snapshot.to_dict() or {}


def read_at(identifier, user_id):
    return inbox_state(identifier, user_id).get('read_at')


def _mark_read(transaction, ref):
    # 트랜잭션으로 최초 읽음 시각을 보존한다.
    if not ref.get(transaction=transaction).exists:
        transaction.create(ref, {'read_at': firestore.SERVER_TIMESTAMP})


def mark_read(identifier, user_id):
    ref = _receipt(collection().document(str(identifier)), user_id)
    firestore.transactional(_mark_read)(ref._client.transaction(), ref)
    return read_at(identifier, user_id)


def exclude_actor(payload):
    """직접 작업한 사용자는 제외하고 자동 재알림 대상은 유지한다."""
    # 앱 내 알림과 푸시가 같은 수신자 목록을 사용하도록 저장 전에 작업자를 제외한다.
    actor = payload.get('actor_id')
    if actor and payload.get('notification_type') != 'schedule_reminder':
        return {**payload, 'recipient_ids': [
            user_id for user_id in payload['recipient_ids'] if user_id != actor]}
    return payload


def _prepare(transaction, ref, payload):
    payload = exclude_actor(payload)
    snapshot = ref.get(transaction=transaction)
    if snapshot.exists:
        old = snapshot.to_dict()
        if any(old[key] != payload[key] for key in ('family_room_id', 'schedule_created_at')):
            raise ValueError('Schedule identity mismatch')
        return  # 재시도해도 최초 수신자와 읽음 상태를 유지한다.
    transaction.create(ref, {**payload, 'status': 'pending', 'created_at': firestore.SERVER_TIMESTAMP})


def prepare(payload):
    ref = collection().document(str(payload['schedule_seq']))
    firestore.transactional(_prepare)(ref._client.transaction(), ref, payload)


def _publish(transaction, ref, fingerprint):
    snapshot = ref.get(transaction=transaction)
    if not snapshot.exists:
        return False
    event = snapshot.to_dict()
    if event['schedule_created_at'] != fingerprint:
        return False
    if event['status'] == 'pending':
        values = {'status': 'published', 'published_at': firestore.SERVER_TIMESTAMP}
        # 일정 안내·재수락 요청이 처음 발행될 때만 큐에 넣어 중복을 막는다.
        if supports_push(event):
            values['push_pending'] = True
        transaction.update(ref, values)
    return True


def publish(identifier, fingerprint):
    ref = collection().document(str(identifier))
    return firestore.transactional(_publish)(ref._client.transaction(), ref, fingerprint)


def hide_many(identifiers, user_id):
    """공용 알림·다른 가족의 읽음은 보존하고 본인 문서만 병합 갱신한다."""
    identifiers = list(identifiers)
    for offset in range(0, len(identifiers), 400):
        target = collection()
        batch = target._client.batch()
        for identifier in identifiers[offset:offset + 400]:
            batch.set(_receipt(target.document(str(identifier)), user_id),
                      {'deleted_at': firestore.SERVER_TIMESTAMP}, merge=True)
        batch.commit(timeout=10)


def mark_many_read(identifiers, user_id):
    """조회에서 확인한 미읽음 항목의 개인 수신 기록만 갱신한다."""
    identifiers = list(identifiers)
    for offset in range(0, len(identifiers), 400):
        target = collection()
        batch = target._client.batch()
        for identifier in identifiers[offset:offset + 400]:
            # 삭제 표시와 다른 가족의 읽음 기록은 그대로 둔다.
            batch.set(_receipt(target.document(str(identifier)), user_id),
                      {'read_at': firestore.SERVER_TIMESTAMP}, merge=True)
        batch.commit(timeout=10)
