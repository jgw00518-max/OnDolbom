"""탈퇴 후 30일 경과 계정 정리. 공유 기록의 외래키만 익명 사용자 행으로 보존한다."""
import logging
import os
from pathlib import Path
from hashlib import sha256
from dotenv import dotenv_values
from firebase_admin import auth, firestore
from google.cloud.firestore_v1.base_query import FieldFilter
from python.database import connect
from python.features.auth.firebase_auth import get_firebase_app
from python.features.family_room.membership import end_membership
from python.features.activity.cache import badge_cache

logger = logging.getLogger(__name__)


def erase_cloud_identity(uid, user_id, email):
    """재시도 가능한 개인 기기·수신 기록 제거와 공유 알림 작성자 익명화."""
    app = get_firebase_app()
    db = firestore.client(app=app)
    # 모든 알림을 스캔하지 않고 해당 사용자가 수신하거나 작성한 문서만 조회한다.
    notifications = db.collection('schedule_notifications')
    for snapshot in notifications.where(filter=FieldFilter('recipient_ids', 'array_contains', user_id)).stream(timeout=15):
        # 수신자 제거와 개인 읽음 기록 삭제를 함께 확정해 부분 실패도 재시도 가능하게 한다.
        batch = db.batch()
        batch.update(snapshot.reference, {'recipient_ids': firestore.ArrayRemove([user_id])})
        batch.delete(snapshot.reference.collection('reads').document(sha256(user_id.encode()).hexdigest()))
        batch.commit(timeout=15)
    for snapshot in notifications.where(filter=FieldFilter('actor_id', '==', user_id)).stream(timeout=15):
        snapshot.reference.update({'actor_name': '탈퇴한 사용자'}, timeout=10)
    for snapshot in db.collection('push_devices').where(filter=FieldFilter('user_uid', '==', uid)).stream(timeout=15):
        snapshot.reference.delete(timeout=10)
    # 이메일 OTP 문서는 현재 서비스의 이메일 HMAC 키로 찾는다. 비밀값은 출력하지 않는다.
    config = {**dotenv_values(Path(__file__).resolve().parents[2] / '.env'), **os.environ}
    if email and config.get('PASSWORD_RESET_SECRET'):
        from python.features.auth.password_reset import digest
        identifier = digest(config['PASSWORD_RESET_SECRET'], 'email:' + email.lower())
        for purpose in ('signup', 'password_reset'):
            db.collection(f'{purpose}_challenges').document(identifier).delete(timeout=10)
    try:
        auth.delete_user(uid, app=app)
    except auth.UserNotFoundError:
        pass


def purge_account(user_id):
    connection = connect()
    try:
        with connection.cursor() as cursor:
            # 역할 변경·재활성화와 같은 잠금 순서를 지키며 최종 기한은 잠금 후 재검사한다.
            cursor.execute("""SELECT DISTINCT p.family_room_id FROM participate p JOIN family_room f
                ON f.family_room_id=p.family_room_id WHERE p.user_id=%s AND p.left_at IS NULL
                AND f.family_room_deleted_at IS NULL ORDER BY p.family_room_id""", (user_id,))
            rooms = [row['family_room_id'] for row in cursor.fetchall()]
            for room in rooms:
                cursor.execute('SELECT family_room_id FROM family_room WHERE family_room_id=%s FOR UPDATE', (room,))
                cursor.fetchone()
            cursor.execute("""SELECT user_firebase_uid,user_email FROM `user`
                WHERE user_id=%s AND withdrawn_at<=DATE_SUB(CURRENT_TIMESTAMP, INTERVAL 30 DAY)
                AND user_firebase_uid IS NOT NULL FOR UPDATE""", (user_id,))
            user = cursor.fetchone()
            if user is None:
                return False
            for room in rooms:
                end_membership(room, user_id, connection=connection, allow_inactive=True)
            # 개인 문의는 공동 기록이 아니다. 답변 외래키를 먼저 정리한다.
            cursor.execute('DELETE a FROM answer a JOIN question q ON q.question_seq=a.question_seq WHERE q.user_id=%s', (user_id,))
            cursor.execute('DELETE FROM question WHERE user_id=%s', (user_id,))
            cursor.execute('DELETE r FROM chat_read_status r JOIN participate p ON p.participate_seq=r.participate_seq WHERE p.user_id=%s', (user_id,))
            if user['user_email']:
                cursor.execute("UPDATE invite SET invite_email=%s WHERE invite_email=%s", (f'{user_id}@deleted.invalid', user['user_email']))
            # 외부 삭제가 실패하면 DB는 롤백된다. 30일 경과 계정은 복구 불가라 재시도해도 재활성화와 경합하지 않는다.
            erase_cloud_identity(user['user_firebase_uid'], user_id, user['user_email'])
            cursor.execute("""UPDATE `user` SET user_firebase_uid=NULL,user_email=NULL,
                user_password=NULL,name='탈퇴한 사용자',phone=NULL WHERE user_id=%s""", (user_id,))
        connection.commit()
        badge_cache.invalidate(user['user_firebase_uid'])
        return True
    except Exception:
        connection.rollback()
        raise
    finally:
        connection.close()


def check_account_cleanup():
    connection = connect()
    try:
        with connection.cursor() as cursor:
            cursor.execute("""SELECT user_id FROM `user` WHERE withdrawn_at<=DATE_SUB(CURRENT_TIMESTAMP, INTERVAL 30 DAY)
                AND user_firebase_uid IS NOT NULL ORDER BY withdrawn_at LIMIT 20""")
            ids = [row['user_id'] for row in cursor.fetchall()]
    finally:
        connection.close()
    completed = 0
    for identifier in ids:
        try:
            completed += int(purge_account(identifier))
        except Exception:
            logger.exception('30일 경과 계정 정리 실패; 다음 주기에 재시도')
    return completed
