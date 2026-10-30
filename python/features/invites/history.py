"""초대 원본을 유지하고 사용자·초대함별 처리 기록만 숨긴다."""
from hashlib import sha256
import logging
from firebase_admin import firestore
from fastapi import HTTPException
from python.features.auth.firebase_auth import get_firebase_app

COMPLETED = frozenset({'수락', '거절', '취소', '만료'})
logger = logging.getLogger(__name__)


def hidden_ref(db, user_id, side, row):
    owner = sha256(user_id.encode()).hexdigest()
    key = sha256(f"{side}:{row['invite_id']}:{row['invite_at']}".encode()).hexdigest()
    return db.collection('invite_history_views').document(owner).collection('hidden').document(key)


def visible_history(rows, user_id, side):
    if not rows:
        return rows
    try:
        db = firestore.client(app=get_firebase_app())
        refs = [hidden_ref(db, user_id, side, row) for row in rows]
        hidden = {snap.reference.path for snap in db.get_all(refs, timeout=10) if snap.exists}
        # 대기 중인 초대는 숨김 기록이 잘못 존재해도 처리 기회를 유지한다.
        return [row for row, ref in zip(rows, refs)
                if row['invite_status'] not in COMPLETED or ref.path not in hidden]
    except HTTPException:
        raise
    except Exception:
        logger.exception('개인 초대 기록 조회 실패')
        raise HTTPException(503, '초대 기록을 불러오지 못했습니다. 다시 시도해 주세요.') from None


def delete_history(conn, current_user, side, invite_ids):
    ids = list(dict.fromkeys(invite_ids))
    placeholders = ','.join(['%s'] * len(ids))
    # 발신자 또는 인증 계정의 수신 이메일을 서버에서 검증한다.
    with conn.cursor() as cursor:
        if side == 'sent':
            cursor.execute(f"""SELECT DISTINCT i.invite_id, i.invite_at, i.invite_status
                FROM invite i JOIN family_room f ON f.family_room_id=i.family_room_id
                JOIN participate p ON p.family_room_id=i.family_room_id
                WHERE i.invite_id IN ({placeholders}) AND i.inviter_id=%s
                AND p.user_id=%s AND p.left_at IS NULL
                AND f.family_room_deleted_at IS NULL AND i.invite_deleted_at IS NULL""",
                (*ids, current_user['user_id'], current_user['user_id']))
        else:
            email = (current_user.get('user_email') or '').strip().lower()
            if not email:
                raise HTTPException(403, '사용자 이메일을 확인할 수 없습니다.')
            cursor.execute(f"""SELECT i.invite_id, i.invite_at, i.invite_status
                FROM invite i JOIN family_room f ON f.family_room_id=i.family_room_id
                JOIN `user` sender ON sender.user_id=i.inviter_id
                WHERE i.invite_id IN ({placeholders}) AND LOWER(TRIM(i.invite_email))=%s
                AND f.family_room_deleted_at IS NULL AND sender.withdrawn_at IS NULL
                AND i.invite_deleted_at IS NULL""", (*ids, email))
        rows = cursor.fetchall()
    eligible = [row for row in rows if row['invite_status'] in COMPLETED]
    if not eligible:
        return 0
    try:
        db = firestore.client(app=get_firebase_app())
        batch = db.batch()
        for row in eligible:
            batch.set(hidden_ref(db, current_user['user_id'], side, row),
                dict(invite_id=row['invite_id'], side=side, hidden_at=firestore.SERVER_TIMESTAMP))
        batch.commit(timeout=10)
        return len(eligible)
    except HTTPException:
        raise
    except Exception:
        logger.exception('개인 초대 기록 삭제 실패')
        raise HTTPException(503, '초대 기록을 삭제하지 못했습니다. 다시 조회해 주세요.') from None
