from unittest import TestCase
from unittest.mock import MagicMock, patch
from fastapi import HTTPException
from fastapi.testclient import TestClient
from firebase_admin import auth
from python.main import app
from python.features.auth import kakao_auth

BASE = 'python.features.auth.kakao_auth.'


class KakaoTests(TestCase):
    def verify(self, info=None, profile=None):
        with patch.dict('os.environ', {'KAKAO_APP_ID': '1622719'}), patch(
            BASE + '_kakao_get', side_effect=[
                info if info is not None else dict(app_id=1622719, id=7, expires_in=60),
                profile if profile is not None else dict(id=7, kakao_account=dict(
                    email='family@example.com', is_email_valid=True, is_email_verified=True)),
            ]):
            return kakao_auth.verify_kakao_user('private-token')

    def test_verified_provider_identity_is_used(self):
        self.assertEqual(self.verify(), ('kakao:7', 'family@example.com'))

    def test_other_app_or_expired_token_rejected(self):
        for info in [dict(app_id=999, id=7, expires_in=60), dict(app_id=1622719, id=7, expires_in=0)]:
            with self.assertRaises(HTTPException) as error:
                self.verify(info=info)
            self.assertEqual(error.exception.status_code, 401)

    def test_unverified_email_or_identity_mismatch_rejected(self):
        for profile in [dict(id=8), dict(id=7, kakao_account=dict(
                email='family@example.com', is_email_valid=True, is_email_verified=False))]:
            with self.assertRaises(HTTPException):
                self.verify(profile=profile)

    def test_custom_token_is_not_cached_and_client_email_is_not_trusted(self):
        with TestClient(app) as client, patch(BASE + 'verify_kakao_user', return_value=('kakao:7', 'verified@example.com')), patch(
                BASE + 'create_kakao_custom_token', return_value='firebase-token') as create:
            response = client.post('/auth/kakao', json={'access_token': 'token', 'email': 'forged@example.com'})
        self.assertEqual(response.status_code, 200)
        self.assertEqual(response.headers['cache-control'], 'no-store')
        create.assert_called_once_with('kakao:7', 'verified@example.com')

    def test_existing_email_is_never_automatically_linked(self):
        with patch(BASE + 'get_firebase_app'), patch(BASE + 'auth.get_user', side_effect=auth.UserNotFoundError('missing')), patch(
                BASE + 'auth.create_user', side_effect=auth.EmailAlreadyExistsError('exists', None, None)), patch(BASE + 'auth.create_custom_token') as mint:
            with self.assertRaises(HTTPException) as error:
                kakao_auth.create_kakao_custom_token('kakao:7', 'old@example.com')
        self.assertEqual(error.exception.status_code, 409)
        mint.assert_not_called()

    def test_disabled_user_cannot_get_custom_token(self):
        with patch(BASE + 'get_firebase_app'), patch(BASE + 'auth.get_user', return_value=MagicMock(disabled=True)), patch(
                BASE + 'auth.create_custom_token') as mint:
            with self.assertRaises(HTTPException) as error:
                kakao_auth.create_kakao_custom_token('kakao:7', 'old@example.com')
        self.assertEqual(error.exception.status_code, 403)
        mint.assert_not_called()

    def test_provider_network_error_is_sanitized(self):
        with patch(BASE + 'requests.get', side_effect=kakao_auth.requests.Timeout('private-token')):
            with self.assertRaises(HTTPException) as error:
                kakao_auth._kakao_get('/v2/user/me', 'private-token')
        self.assertEqual(error.exception.status_code, 503)
        self.assertNotIn('private-token', error.exception.detail)

    def test_repeated_login_reuses_same_firebase_uid(self):
        user = MagicMock(disabled=False, email='family@example.com')
        with patch(BASE + 'get_firebase_app'), patch(BASE + 'auth.get_user', return_value=user), patch(
                BASE + 'auth.create_custom_token', return_value=b'token') as mint, patch(BASE + 'auth.create_user') as create:
            self.assertEqual(kakao_auth.create_kakao_custom_token('kakao:7', user.email), 'token')
        create.assert_not_called()
        self.assertEqual(mint.call_args.args, ('kakao:7',))
