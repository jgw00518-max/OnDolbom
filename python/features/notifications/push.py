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


# 설치 식별자는 계정과 별개이며, 세대 번호로 늦게 도착한 이전 연결 요청을 차단한다.
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
    # 서버에는 연결 비밀값의 원문 대신 해시만 보관한다.
    secret_hash = digest(payload.secret.get_secret_value())
    if previous and not compare_digest(previous.get('secret_hash', ''), secret_hash):
        raise HTTPException(409, '기기 등록 정보를 확인해 주세요.')
    # 계정 전환 뒤 이전 요청이 새 연결을 덮어쓰지 못하도록 순서를 검사한다.
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
        # 요청 본문의 사용자 정보가 아니라 검증된 Firebase 계정으로 MySQL 사용자를 찾는다.
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
    # 이벤트·기기별 처리권을 2분 동안 확보해 여러 worker의 동시 발송을 줄인다.
    snapshot = ref.get(transaction=transaction, timeout=10)
    old = snapshot.to_dict() if snapshot.exists else {}
    if old.get('status') in {'sent', 'skipped', 'failed'}:
        return False
    if old.get('lease_until', now) > now or old.get('next_attempt_at', now) > now:
        return False
    # 영구 장애가 반복되어도 무한 재시도하지 않는다.
    if old.get('attempts', 0) >= 5:
        transaction.update(ref, {'status': 'failed', 'lease_until': now})
        return False
    attempts = old.get('attempts', 0) + 1
    transaction.set(ref, dict(status='processing', attempts=attempts,
        lease_until=now + timedelta(minutes=2), updated_at=now))
    return attempts


def send_message(fid, uid, identifier, test=False, notification_type='schedule_created', family_room_id=None, chat_seq=None):
    # 잠금 화면에는 대상자 건강정보나 메모를 노출하지 않는다.
    return messaging.send(messaging.Message(fid=fid,
        notification=messaging.Notification(title='온돌봄', body='푸시 연결 테스트입니다.' if test else {
            'chat_message': '가족의 새 채팅이 도착했습니다. 앱에서 확인해 주세요.',
            'schedule_created': '새 돌봄 일정이 등록되었습니다. 앱에서 확인해 주세요.',
            'schedule_changed': '돌봄 일정이 변경되었습니다. 앱에서 확인해 주세요.',
            'schedule_deleted': '돌봄 일정이 삭제되었습니다. 앱에서 확인해 주세요.',
            'schedule_accepted': '돌봄 일정이 수락되었습니다. 앱에서 확인해 주세요.',
            'schedule_reconfirmed': '변경된 돌봄 일정이 재수락되었습니다. 앱에서 확인해 주세요.',
            'schedule_declined': '변경된 돌봄 일정의 재수락이 거절되었습니다. 앱에서 확인해 주세요.',
            'schedule_reconfirm_expired': '재수락 응답 기한이 지나 담당 배정이 해제되었습니다. 앱에서 최신 일정을 확인해 주세요.',
            'schedule_reconfirm_unanswered': '담당 가족이 재수락 요청에 응답하지 않아 배정이 해제되었습니다. 새 담당자를 확인해 주세요.',
            'schedule_reconfirm_unverified': '긴급 변경 일정의 재수락이 아직 확인되지 않았습니다. 담당 가족에게 직접 확인해 주세요.',
            'schedule_withdrawn': '담당 가족이 돌봄 일정 참여를 취소했습니다. 새로운 담당자를 확인해 주세요.',
            'schedule_recruitment': '돌봄 일정의 담당자를 다시 모집합니다. 앱에서 확인해 주세요.',
            'schedule_reminder': '시작까지 72시간 이내인 돌봄 일정에 아직 담당자가 없습니다. 앱에서 확인해 주세요.',
            'schedule_reconfirm': '돌봄 일정의 날짜 또는 시간이 변경되었습니다. 앱에서 재수락 여부를 확인해 주세요.',
        }[notification_type]),
        data={'notification_id': str(identifier), 'user_uid': uid, 'type': 'test' if test else notification_type,
              **({'family_room_id': family_room_id, 'chat_seq': str(chat_seq)} if notification_type == 'chat_message' else {})},
        android=messaging.AndroidConfig(priority='high', ttl=timedelta(hours=24),
            notification=messaging.AndroidNotification(channel_id='ondolbom_updates',
                icon='ic_stat_notification', tag=digest('chat_' + family_room_id if notification_type == 'chat_message' else str(identifier))))), app=get_firebase_app())


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


def dispatch_event(identifier, event, *, visible_loader=None, finish_event=True):
    """등록·변경·삭제를 전달한다. 앱 내 알림 저장과 푸시 실패는 분리한다."""
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
                # 같은 알림과 설치 기기 조합은 같은 발송 기록을 사용한다.
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
                    visible = None if user is None else (visible_loader or _visible)(connection, user_id, event)
                    if visible is None:
                        delivery.update({'status': 'skipped', 'lease_until': now}, timeout=10)
                        continue
                    send_message(current['fid'], device['user_uid'], identifier,
                                 # 주보호자는 거절 결과, 다른 가족은 재모집 안내를 받는다.
                                 notification_type=visible.get('notification_type', event.get('notification_type', 'schedule_created')),
                                 **({'family_room_id': event['family_room_id'], 'chat_seq': event['chat_seq']}
                                    if event.get('notification_type') == 'chat_message' else {}))
                    delivery.update({'status': 'sent', 'sent_at': now, 'lease_until': now}, timeout=10)
                except (messaging.UnregisteredError, messaging.SenderIdMismatchError):
                    delivery.update({'status': 'failed', 'error_code': 'invalid_token', 'lease_until': now}, timeout=10)
                    firestore.transactional(_disable_device)(database.transaction(), snapshot.reference, device['generation'])
                except Exception as error:
                    # 일시적 오류는 간격을 늘려 재시도하며, 예외 원문에 포함될 수 있는 키는 저장하지 않는다.
                    delivery.update({'status': 'failed' if attempts >= 5 else 'pending',
                        'next_attempt_at': now + timedelta(seconds=min(30 * 2 ** (attempts - 1), 600)),
                        'lease_until': now, 'error_code': type(error).__name__}, timeout=10)
                    terminal &= attempts >= 5
        # 모든 기기가 성공·건너뜀·최종 실패 상태일 때만 큐에서 제거한다.
        if terminal and finish_event:
            store.collection().document(str(identifier)).update({'push_pending': False}, timeout=10)
        return terminal
    finally:
        connection.close()


def check_push_notifications():
    # 첫 발행 시 표시된 작업만 읽어 과거 알림을 소급 발송하지 않는다.
    events = store.collection().where(filter=FieldFilter('push_pending', '==', True)).limit(30).stream(timeout=10)
    pending = 0
    for snapshot in events:
        event = snapshot.to_dict()
        if event.get('status') != 'published' or not store.supports_push(event):
            continue
        pending += 1
        try:
            dispatch_event(snapshot.id, event)
        except Exception:
            # 토큰·본문을 로그에 남기지 않고 다음 검사에서 같은 작업을 재시도한다.
            logger.error('푸시 작업 처리 실패; 다음 검사에서 재시도')

    return pending
