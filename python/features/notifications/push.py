"""FCM 기기 등록과 발송. Firestore에는 서버 Admin SDK만 접근한다."""
from datetime import datetime, timedelta, timezone
from hashlib import sha256
from secrets import compare_digest
import logging
from uuid import uuid4

from fastapi import APIRouter, Depends, HTTPException
from pydantic import BaseModel, ConfigDict, Field, SecretStr
from firebase_admin import firestore, messaging
from google.cloud.firestore_v1.base_query import FieldFilter
from python.database import connect
from python.features.auth.firebase_auth import get_firebase_app, require_firebase_user
from python.features.notifications import store
from python.features.schedules.notification_router import _user_id, _visible

router = APIRouter(prefix='/push', tags=['push'])
logger = logging.getLogger(__name__)


def db():
    return firestore.client(app=get_firebase_app())


def digest(value):
    return sha256(value.encode()).hexdigest()


class Installation(BaseModel):
    model_config = ConfigDict(extra='forbid')
    installation_id: str = Field(pattern=r'^[a-f0-9]{32}$')
    secret: SecretStr
    generation: int = Field(ge=1)


class Registration(Installation):
    fid: SecretStr


def validate_secret(payload):
    if len(payload.secret.get_secret_value()) != 64:
        raise HTTPException(422, '기기 등록 정보를 확인해 주세요.')


def _bind(transaction, ref, payload, uid, user_id, enabled):
    old = ref.get(transaction=transaction, timeout=10)
    previous = old.to_dict() if old.exists else {}
    secret_hash = digest(payload.secret.get_secret_value())
    if previous and not compare_digest(previous.get('secret_hash', ''), secret_hash):
        raise HTTPException(409, '기기 등록 정보를 확인해 주세요.')
    generation = previous.get('generation', 0)
    if payload.generation < generation or (payload.generation == generation and previous.get('user_uid') != uid):
        raise HTTPException(409, '이미 변경된 기기 연결입니다.')
    if not enabled and previous and previous.get('user_uid') != uid:
        raise HTTPException(403, '본인 기기 연결만 해제할 수 있습니다.')
    now = datetime.now(timezone.utc)
    transaction.set(ref, dict(secret_hash=secret_hash, user_uid=uid, user_id=user_id,
        fid=payload.fid.get_secret_value() if enabled else None, enabled=enabled,
        generation=payload.generation, updated_at=now, expires_at=now + timedelta(days=30)))


def bind(payload, claims, enabled):
    validate_secret(payload)
    if enabled and not 20 <= len(payload.fid.get_secret_value()) <= 4096:
        raise HTTPException(422, '기기 토큰을 확인해 주세요.')
    connection = None
    try:
        connection = connect()
        user_id = _user_id(connection, claims)
        ref = db().collection('push_devices').document(digest(payload.installation_id))
        firestore.transactional(_bind)(ref._client.transaction(), ref, payload, claims['uid'], user_id, enabled)
        return {'registered': enabled}
    except HTTPException:
        raise
    except Exception:
        raise HTTPException(503, '푸시 기기 연결을 처리하지 못했습니다.') from None
    finally:
        if connection is not None:
            connection.close()


@router.post('/devices')
def register(payload: Registration, claims: dict = Depends(require_firebase_user)):
    return bind(payload, claims, True)


@router.post('/devices/unregister')
def unregister(payload: Installation, claims: dict = Depends(require_firebase_user)):
    return bind(payload, claims, False)


def _claim(transaction, ref, now):
    snapshot = ref.get(transaction=transaction, timeout=10)
    old = snapshot.to_dict() if snapshot.exists else {}
    if old.get('status') in {'sent', 'skipped', 'failed'}:
        return False
    if old.get('lease_until', now) > now or old.get('next_attempt_at', now) > now:
        return False
    if old.get('attempts', 0) >= 5:
        transaction.update(ref, {'status': 'failed', 'lease_until': now})
        return False
    attempts = old.get('attempts', 0) + 1
    transaction.set(ref, dict(status='processing', attempts=attempts,
        lease_until=now + timedelta(minutes=2), updated_at=now))
    return attempts


def send_message(fid, uid, identifier, test=False):
    # 잠금 화면에는 대상자 건강정보나 메모를 노출하지 않는다.
    return messaging.send(messaging.Message(fid=fid,
        notification=messaging.Notification(title='온돌봄', body='푸시 연결 테스트입니다.' if test else '새 돌봄 일정이 등록되었습니다. 앱에서 확인해 주세요.'),
        data={'notification_id': str(identifier), 'user_uid': uid, 'type': 'test' if test else 'schedule_created'},
        android=messaging.AndroidConfig(priority='high', ttl=timedelta(hours=24),
            notification=messaging.AndroidNotification(channel_id='ondolbom_updates',
                icon='ic_stat_notification', tag=digest(str(identifier))))), app=get_firebase_app())


@router.post('/test')
def test_push(payload: Installation, claims: dict = Depends(require_firebase_user)):
    validate_secret(payload)
    connection = None
    try:
        connection = connect()
        user_id = _user_id(connection, claims)
        row = db().collection('push_devices').document(digest(payload.installation_id)).get(timeout=10)
        device = row.to_dict() if row.exists else {}
        if (device.get('user_uid') != claims['uid'] or device.get('user_id') != user_id or not device.get('enabled')
                or device.get('expires_at', datetime.now(timezone.utc)) <= datetime.now(timezone.utc)
                or device.get('generation') != payload.generation
                or not compare_digest(device.get('secret_hash', ''), digest(payload.secret.get_secret_value()))):
            raise HTTPException(403, '현재 계정의 기기 연결을 먼저 확인해 주세요.')
        send_message(device['fid'], claims['uid'], 'test_' + uuid4().hex, test=True)
        return {'sent': True}
    except HTTPException:
        raise
    except Exception:
        raise HTTPException(503, 'FCM 권한·API 활성화 및 기기 연결을 확인해 주세요.') from None
    finally:
        if connection is not None:
            connection.close()


def _disable_device(transaction, ref, generation):
    snapshot = ref.get(transaction=transaction, timeout=10)
    current = snapshot.to_dict() if snapshot.exists else {}
    if current.get('generation') == generation:
        transaction.update(ref, {'enabled': False})


def dispatch_event(identifier, event):
    """등록 알림 한 종류부터 연결한다. 앱 내 알림 저장과 푸시 실패는 분리한다."""
    database = db()
    terminal = True
    connection = connect()
    try:
        for user_id in event.get('recipient_ids', []):
            devices = database.collection('push_devices').where(filter=FieldFilter('user_id', '==', user_id)).stream(timeout=10)
            for snapshot in devices:
                device = snapshot.to_dict()
                now = datetime.now(timezone.utc)
                if not device.get('enabled') or device.get('expires_at', now) <= now:
                    continue
                delivery = database.collection('push_deliveries').document(digest(str(identifier) + '|' + snapshot.id))
                attempts = firestore.transactional(_claim)(database.transaction(), delivery, now)
                if not attempts:
                    saved = delivery.get(timeout=10).to_dict() or {}
                    terminal &= saved.get('status') in {'sent', 'skipped', 'failed'}
                    continue
                try:
                    # 발송 직전에 기기 계정 연결·회원·공간 참여·일정 삭제를 다시 확인한다.
                    current = snapshot.reference.get(timeout=10).to_dict() or {}
                    if not current.get('enabled') or current.get('generation') != device['generation'] or current.get('user_uid') != device['user_uid']:
                        delivery.update({'status': 'skipped', 'lease_until': now}, timeout=10)
                        continue
                    with connection.cursor() as cursor:
                        cursor.execute('''SELECT user_id FROM `user` WHERE user_id=%s
                            AND BINARY user_firebase_uid=BINARY %s AND withdrawn_at IS NULL''', (user_id, device['user_uid']))
                        user = cursor.fetchone()
                    if user is None or _visible(connection, user_id, event) is None:
                        delivery.update({'status': 'skipped', 'lease_until': now}, timeout=10)
                        continue
                    send_message(current['fid'], device['user_uid'], identifier)
                    delivery.update({'status': 'sent', 'sent_at': now, 'lease_until': now}, timeout=10)
                except (messaging.UnregisteredError, messaging.SenderIdMismatchError):
                    delivery.update({'status': 'failed', 'error_code': 'invalid_token', 'lease_until': now}, timeout=10)
                    firestore.transactional(_disable_device)(database.transaction(), snapshot.reference, device['generation'])
                except Exception as error:
                    delivery.update({'status': 'failed' if attempts >= 5 else 'pending',
                        'next_attempt_at': now + timedelta(seconds=min(30 * 2 ** (attempts - 1), 600)),
                        'lease_until': now, 'error_code': type(error).__name__}, timeout=10)
                    terminal &= attempts >= 5
        if terminal:
            store.collection().document(str(identifier)).update({'push_pending': False}, timeout=10)
    finally:
        connection.close()


def check_push_notifications():
    events = store.collection().where(filter=FieldFilter('push_pending', '==', True)).limit(30).stream(timeout=10)
    for snapshot in events:
        event = snapshot.to_dict()
        if event.get('status') != 'published' or event.get('notification_type', 'schedule_created') != 'schedule_created':
            continue
        try:
            dispatch_event(snapshot.id, event)
        except Exception:
            # 토큰·본문을 로그에 남기지 않고 다음 검사에서 같은 작업을 재시도한다.
            logger.error('푸시 작업 처리 실패; 다음 검사에서 재시도')
