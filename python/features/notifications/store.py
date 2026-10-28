"""Firestore 알림 저장. 클라이언트는 API를 통해서만 접근한다."""
from hashlib import sha256

from firebase_admin import firestore
from google.cloud.firestore_v1.base_query import FieldFilter
from python.features.auth.firebase_auth import get_firebase_app


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


def read_at(identifier, user_id):
    snapshot = _receipt(collection().document(str(identifier)), user_id).get(timeout=10)
    return (snapshot.to_dict() or {}).get('read_at')


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
        # 신규 일정 등록만 푸시 큐에 넣는다. 재발행·읽음 갱신은 재발송하지 않는다.
        if event.get('notification_type', 'schedule_created') == 'schedule_created':
            values['push_pending'] = True
        transaction.update(ref, values)
    return True


def publish(identifier, fingerprint):
    ref = collection().document(str(identifier))
    return firestore.transactional(_publish)(ref._client.transaction(), ref, fingerprint)
