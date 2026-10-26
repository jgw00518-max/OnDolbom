"""카카오 액세스 토큰을 검증하고 Firebase Custom Token으로 교환한다."""
import os
import re
from pathlib import Path

import requests
from dotenv import dotenv_values
from fastapi import APIRouter, HTTPException, Response
from firebase_admin import auth, exceptions
from pydantic import BaseModel, SecretStr

from python.features.auth.firebase_auth import get_firebase_app

router = APIRouter()


class KakaoTokenRequest(BaseModel):
    # repr·일반 로깅 시 토큰 원문이 노출되지 않게 한다.
    access_token: SecretStr


def _kakao_get(path, token):
    try:
        # URL은 서버 상수만 허용하며 토큰을 URL이나 로그에 포함하지 않는다.
        result = requests.get('https://kapi.kakao.com' + path,
                              headers={'Authorization': f'Bearer {token}'},
                              timeout=(5, 8), allow_redirects=False)
        if result.status_code == 401:
            raise HTTPException(401, '카카오 인증이 만료되었습니다. 다시 로그인해 주세요.')
        if result.status_code != 200:
            raise HTTPException(503, '카카오 인증 서버에 연결하지 못했습니다.')
        body = result.json()
        if not isinstance(body, dict):
            raise ValueError('Invalid response')
        return body
    except (requests.RequestException, ValueError):
        raise HTTPException(503, '카카오 인증 서버에 연결하지 못했습니다.') from None


def verify_kakao_user(token):
    values = {**dotenv_values(Path(__file__).resolve().parents[2] / '.env'), **os.environ}
    app_id = values.get('KAKAO_APP_ID', '')
    if not app_id.isdigit():
        raise HTTPException(503, '서버 KAKAO_APP_ID 설정이 필요합니다.')
    info = _kakao_get('/v1/user/access_token_info', token)
    # 다른 서비스에서 발급받은 유효한 토큰도 온돌봄에는 사용할 수 없다.
    if str(info.get('app_id')) != app_id or not isinstance(info.get('expires_in'), int) or info['expires_in'] <= 0:
        raise HTTPException(401, '온돌봄의 유효한 카카오 로그인 정보가 아닙니다.')
    profile = _kakao_get('/v2/user/me', token)
    identifier = profile.get('id')
    if type(identifier) is not int or identifier <= 0 or identifier != info.get('id'):
        raise HTTPException(401, '카카오 계정 정보를 확인하지 못했습니다.')
    account = profile.get('kakao_account') or {}
    email = account.get('email')
    if (account.get('is_email_valid') is not True or account.get('is_email_verified') is not True
            or not isinstance(email, str) or len(email) > 200
            or not re.fullmatch(r'[^\s@]+@[^\s@]+\.[^\s@]+', email)):
        raise HTTPException(422, '카카오계정의 인증된 이메일 제공 동의가 필요합니다.')
    return f'kakao:{identifier}', email


def create_kakao_custom_token(uid, email):
    app = get_firebase_app()
    try:
        try:
            user = auth.get_user(uid, app=app)
        except auth.UserNotFoundError:
            # 동일 이메일의 기존 계정을 인증 없이 자동 연결하지 않는다.
            try:
                user = auth.create_user(uid=uid, email=email, email_verified=True, app=app)
            except auth.UidAlreadyExistsError:
                user = auth.get_user(uid, app=app)  # 동시 최초 로그인 재시도
        if user.disabled:
            raise HTTPException(403, '사용이 중지된 계정입니다.')
        if not user.email or user.email.lower() != email.lower():
            raise HTTPException(409, '카카오 이메일이 변경되었습니다. 기존 계정 연결을 확인해 주세요.')
        return auth.create_custom_token(uid, app=app).decode('utf-8')
    except auth.EmailAlreadyExistsError:
        raise HTTPException(409, '동일 이메일의 기존 계정이 있습니다. 기존 가입 방식으로 로그인해 주세요.') from None
    except (exceptions.FirebaseError, ValueError):
        raise HTTPException(503, 'Firebase 카카오 로그인을 처리하지 못했습니다.') from None


@router.post('/kakao')
def kakao_login(payload: KakaoTokenRequest, response: Response):
    token = payload.access_token.get_secret_value()
    if not 1 <= len(token) <= 4096 or any(character.isspace() for character in token):
        raise HTTPException(400, '유효한 카카오 토큰이 필요합니다.')
    uid, email = verify_kakao_user(token)
    response.headers['Cache-Control'] = 'no-store'
    return {'custom_token': create_kakao_custom_token(uid, email)}
