"""공지·답변 읽음 기록. Firebase UID별로 분리하며 앱의 직접 접근은 허용하지 않는다."""
import json
from hashlib import sha256
from firebase_admin import firestore
from python.features.auth.firebase_auth import get_firebase_app


def fingerprint(value):
    return sha256(json.dumps(value, sort_keys=True, default=str, ensure_ascii=False).encode()).hexdigest()


def notice_token(row):
    return fingerprint({key: row.get(key) for key in (
        'admin_id', 'notice_id', 'notice_title', 'notice_content',
        'notice_created_at', 'notice_updated_at')})


def answer_token(answers):
    return fingerprint([{key: row.get(key) for key in ('answer_seq', 'answer_content', 'answered_at')}
                        for row in sorted(answers, key=lambda row: row['answer_seq'])])


def receipt_key(kind, identity):
    return fingerprint([kind, identity])


def collection(uid):
    return firestore.client(app=get_firebase_app()).collection('activity_reads').document(
        sha256(uid.encode()).hexdigest()).collection('items')


def unread_count(uid, items):
    """목록에 현재 존재하는 항목만 비교해 삭제된 항목은 숫자에서 제외한다."""
    if not items:
        return 0
    refs = [collection(uid).document(key) for key in items]
    snapshots = firestore.client(app=get_firebase_app()).get_all(refs, timeout=10)
    seen = {snap.id: (snap.to_dict() or {}).get('token') for snap in snapshots}
    return sum(seen.get(key) != token for key, token in items.items())


def mark_read(uid, key, token):
    collection(uid).document(key).set({'token': token, 'read_at': firestore.SERVER_TIMESTAMP}, timeout=10)
