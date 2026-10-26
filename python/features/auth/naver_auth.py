"""서버 전용 Client Secret으로 네이버 인가 코드를 교환한다. 로컬 서버 단일 워커용."""
import hashlib
import hmac
import os
import re
import secrets
import time
from pathlib import Path
from threading import Lock
from urllib.parse import urlencode, urlsplit

import requests
from dotenv import dotenv_values
from fastapi import APIRouter, HTTPException, Response
from fastapi.responses import RedirectResponse
from firebase_admin import auth, exceptions
from pydantic import BaseModel, Field, SecretStr

from python.features.auth.firebase_auth import get_firebase_app

router = APIRouter()
_pending = {}
_lock = Lock()
_ttl = 300


class NaverStart(BaseModel):
    challenge: str = Field(pattern=r'^[a-f0-9]{64}$')


class NaverExchange(BaseModel):
    state: str = Field(min_length=20, max_length=200)
    code: SecretStr
    verifier: SecretStr


def _settings():
    values = {**dotenv_values(Path(__file__).resolve().parents[2] / '.env'), **os.environ}
    client_id = (values.get('NAVER_CLIENT_ID') or '').strip()
    secret = (values.get('NAVER_CLIENT_SECRET') or '').strip()
    redirect = (values.get('NAVER_REDIRECT_URI') or '').strip()
    parsed = urlsplit(redirect)
    if (not client_id or not secret or parsed.scheme not in ('http', 'https') or not parsed.netloc
            or parsed.path != '/auth/naver/callback' or parsed.query or parsed.fragment or parsed.username):
        raise HTTPException(503, '서버의 네이버 Client ID·Secret·Callback URL 설정을 확인해 주세요.')
    return client_id, secret, redirect


def _cleanup():
    for state in list(_pending):
        if _pending[state]['expires'] <= time.monotonic():
            del _pending[state]


def _headers(response):
    response.headers['Cache-Control'] = 'no-store'
    response.headers['Referrer-Policy'] = 'no-referrer'


@router.post('/naver/start')
def naver_start(payload: NaverStart, response: Response):
    client_id, _, redirect = _settings()
    state = secrets.token_urlsafe(32)
    with _lock:
        _cleanup()
        if len(_pending) >= 1000:
            raise HTTPException(429, '로그인 요청이 많습니다. 잠시 후 다시 시도해 주세요.')
        _pending[state] = dict(challenge=payload.challenge, expires=time.monotonic() + _ttl,
                               redirect=redirect, client_id=client_id, code_hash=None)
    _headers(response)
    return {'state': state, 'authorization_url': 'https://nid.naver.com/oauth2.0/authorize?' + urlencode(
        dict(response_type='code', client_id=client_id, redirect_uri=redirect, state=state))}


@router.get('/naver/callback')
def naver_callback(state: str = '', code: str = '', error: str = ''):
    # state는 각 서버 메모리에서 관리하므로 다른 PC의 서버로 복귀하면 거부한다.
    with _lock:
        _cleanup()
        entry = _pending.get(state)
        if entry is None:
            raise HTTPException(400, '로그인 요청이 만료됐습니다. 앱에서 다시 시작해 주세요.')
        if error:
            del _pending[state]
        elif not 1 <= len(code) <= 4096:
            raise HTTPException(400, '네이버 인가 코드가 없습니다.')
        else:
            entry['code_hash'] = hashlib.sha256(code.encode()).hexdigest()
    # Firebase 토큰·Client Secret·네이버 액세스 토큰은 브라우저 URL에 넣지 않는다.
    parameters = {'state': state, 'error': 'cancelled'} if error else {'state': state, 'code': code}
    response = RedirectResponse('ondolbomnaver://oauth?' + urlencode(parameters), status_code=302)
    _headers(response)
    return response


def _consume(payload):
    verifier = payload.verifier.get_secret_value()
    code = payload.code.get_secret_value()
    if not re.fullmatch(r'[A-Za-z0-9_-]{43,128}', verifier) or not 1 <= len(code) <= 4096:
        raise HTTPException(400, '유효한 네이버 로그인 요청이 필요합니다.')
    with _lock:
        _cleanup()
        entry = _pending.get(payload.state)
        if entry is None:
            raise HTTPException(401, '로그인 요청이 만료됐거나 이미 처리됐습니다.')
        # 앱만 가진 난수로 복귀 URL을 가로챈 다른 앱의 코드 교환을 차단한다.
        if (not hmac.compare_digest(entry['challenge'], hashlib.sha256(verifier.encode()).hexdigest())
                or not entry['code_hash']
                or not hmac.compare_digest(entry['code_hash'], hashlib.sha256(code.encode()).hexdigest())):
            raise HTTPException(401, '네이버 로그인 요청 정보가 일치하지 않습니다.')
        return _pending.pop(payload.state), code


def _provider_identity(code, state, entry):
    client_id, secret, redirect = _settings()
    if entry['client_id'] != client_id or entry['redirect'] != redirect:
        raise HTTPException(401, '네이버 설정이 변경됐습니다. 로그인을 다시 시작해 주세요.')
    try:
        token_result = requests.post('https://nid.naver.com/oauth2.0/token', data=dict(
            grant_type='authorization_code', client_id=client_id, client_secret=secret,
            redirect_uri=redirect, code=code, state=state), timeout=(5, 8), allow_redirects=False)
        if token_result.status_code != 200:
            raise HTTPException(401 if token_result.status_code < 500 else 503, '네이버 인증에 실패했습니다. 다시 로그인해 주세요.')
        tokens = token_result.json()
        token = tokens.get('access_token') if isinstance(tokens, dict) else None
        if not isinstance(token, str) or not token:
            raise HTTPException(401, '네이버 인증이 만료됐습니다. 다시 로그인해 주세요.')
        profile_result = requests.get('https://openapi.naver.com/v1/nid/me',
            headers={'Authorization': f'Bearer {token}'}, timeout=(5, 8), allow_redirects=False)
        if profile_result.status_code != 200:
            raise HTTPException(503, '네이버 회원정보를 확인하지 못했습니다.')
        body = profile_result.json()
        if not isinstance(body, dict) or body.get('resultcode') != '00' or not isinstance(body.get('response'), dict):
            raise HTTPException(401, '네이버 회원정보가 유효하지 않습니다.')
        profile = body['response']
        identifier, email = profile.get('id'), profile.get('email')
        if not isinstance(identifier, str) or not 1 <= len(identifier) <= 512:
            raise HTTPException(401, '네이버 계정 식별자를 확인하지 못했습니다.')
        if not isinstance(email, str) or len(email) > 200 or not re.fullmatch(r'[^\s@]+@[^\s@]+\.[^\s@]+', email):
            raise HTTPException(422, '네이버 연락처 이메일 제공 동의가 필요합니다.')
        # 이메일 대신 앱별 고유 ID를 사용하고 Firebase UID 길이를 일정하게 유지한다.
        return 'naver:' + hashlib.sha256(identifier.encode()).hexdigest(), email
    except (requests.RequestException, ValueError):
        raise HTTPException(503, '네이버 인증 서버 연결을 확인해 주세요.') from None


def create_naver_custom_token(uid, email):
    app = get_firebase_app()
    try:
        try:
            user = auth.get_user(uid, app=app)
        except auth.UserNotFoundError:
            try:
                # 연락처 이메일 제공만으로 Firebase 이메일 인증을 완료 처리하지 않는다.
                user = auth.create_user(uid=uid, email=email, email_verified=False, app=app)
            except auth.UidAlreadyExistsError:
                user = auth.get_user(uid, app=app)
        if user.disabled:
            raise HTTPException(403, '사용이 중지된 계정입니다.')
        if not user.email or user.email.lower() != email.lower():
            raise HTTPException(409, '연락처 이메일이 변경되었습니다. 기존 계정 연결을 확인해 주세요.')
        return auth.create_custom_token(uid, app=app).decode('utf-8')
    except auth.EmailAlreadyExistsError:
        raise HTTPException(409, '동일 이메일의 기존 계정이 있습니다. 기존 가입 방식으로 로그인해 주세요.') from None
    except (exceptions.FirebaseError, ValueError):
        raise HTTPException(503, 'Firebase 네이버 로그인을 처리하지 못했습니다.') from None


@router.post('/naver/exchange')
def naver_exchange(payload: NaverExchange, response: Response):
    entry, code = _consume(payload)
    uid, email = _provider_identity(code, payload.state, entry)
    _headers(response)
    return {'custom_token': create_naver_custom_token(uid, email)}
