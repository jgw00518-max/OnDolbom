import hashlib
from unittest import TestCase
from unittest.mock import MagicMock, patch
from urllib.parse import parse_qs, urlsplit

from fastapi.testclient import TestClient
from firebase_admin import auth
from python.main import app
from python.features.auth import naver_auth

BASE = 'python.features.auth.naver_auth.'
SETTINGS = ('client-id', 'server-secret', 'http://10.0.2.2:8000/auth/naver/callback')
VERIFIER = 'a' * 43


class NaverTests(TestCase):
    def setUp(self):
        self.client = TestClient(app)
        self.settings = patch(BASE + '_settings', return_value=SETTINGS)
        self.settings.start()
        naver_auth._pending.clear()

    def tearDown(self):
        naver_auth._pending.clear()
        self.settings.stop()
        self.client.close()

    def start(self):
        response = self.client.post('/auth/naver/start', json={
            'challenge': hashlib.sha256(VERIFIER.encode()).hexdigest()})
        self.assertEqual(response.status_code, 200)
        self.assertNotIn('server-secret', response.text)
        return response.json()['state']

    def callback(self, state, code='naver-code'):
        return self.client.get('/auth/naver/callback', params={'state': state, 'code': code}, follow_redirects=False)

    def exchange(self, state, verifier=VERIFIER, code='naver-code'):
        return self.client.post('/auth/naver/exchange', json=dict(state=state, code=code, verifier=verifier))

    def test_start_uses_configured_server_callback(self):
        state = self.start()
        self.assertIn(state, naver_auth._pending)
        self.assertEqual(naver_auth._pending[state]['redirect'], SETTINGS[2])

    def test_unknown_state_cannot_redirect_to_app(self):
        response = self.callback('unknown-state')
        self.assertEqual(response.status_code, 400)
        self.assertNotIn('location', response.headers)

    def test_callback_only_returns_code_and_state(self):
        state = self.start()
        response = self.callback(state)
        target = urlsplit(response.headers['location'])
        self.assertEqual(target.scheme, 'ondolbomnaver')
        self.assertEqual(parse_qs(target.query), dict(state=[state], code=['naver-code']))
        self.assertEqual(response.headers['cache-control'], 'no-store')

    def test_intercepted_callback_needs_original_app_verifier(self):
        state = self.start()
        self.callback(state)
        with patch(BASE + '_provider_identity') as identity:
            self.assertEqual(self.exchange(state, verifier='b' * 43).status_code, 401)
            identity.assert_not_called()
        self.assertIn(state, naver_auth._pending)

    def test_code_not_seen_at_server_callback_is_rejected(self):
        state = self.start()
        self.assertEqual(self.exchange(state).status_code, 401)
        self.callback(state)
        self.assertEqual(self.exchange(state, code='forged-code').status_code, 401)

    def test_success_is_one_use_and_returns_no_store_token(self):
        state = self.start()
        self.callback(state)
        with patch(BASE + '_provider_identity', return_value=('naver:stable', 'contact@example.com')), patch(
                BASE + 'create_naver_custom_token', return_value='firebase-token') as mint:
            response = self.exchange(state)
            self.assertEqual(response.status_code, 200)
            self.assertEqual(response.json(), dict(custom_token='firebase-token'))
            self.assertEqual(response.headers['cache-control'], 'no-store')
            mint.assert_called_once_with('naver:stable', 'contact@example.com')
            self.assertEqual(self.exchange(state).status_code, 401)

    def test_expired_session_is_rejected(self):
        state = self.start()
        naver_auth._pending[state]['expires'] = 0
        self.assertEqual(self.callback(state).status_code, 400)

    def test_cancel_removes_pending_request(self):
        state = self.start()
        response = self.client.get('/auth/naver/callback', params={'state': state, 'error': 'access_denied'}, follow_redirects=False)
        self.assertIn('error=cancelled', response.headers['location'])
        self.assertNotIn(state, naver_auth._pending)

    def test_provider_exchange_keeps_secret_in_server_post_body(self):
        tokens = MagicMock(status_code=200)
        tokens.json.return_value = dict(access_token='naver-access')
        profile = MagicMock(status_code=200)
        profile.json.return_value = dict(resultcode='00', response=dict(id='provider-stable-id', email='contact@gmail.com'))
        with patch(BASE + 'requests.post', return_value=tokens) as post, patch(BASE + 'requests.get', return_value=profile):
            uid, email = naver_auth._provider_identity('code', 'state', dict(client_id=SETTINGS[0], redirect=SETTINGS[2]))
        self.assertEqual(uid, 'naver:' + hashlib.sha256(b'provider-stable-id').hexdigest())
        self.assertEqual(email, 'contact@gmail.com')
        self.assertEqual(post.call_args.kwargs['data']['client_secret'], SETTINGS[1])
        self.assertNotIn(SETTINGS[1], post.call_args.args[0])

    def test_contact_email_is_not_marked_verified_or_merged(self):
        with patch(BASE + 'get_firebase_app'), patch(BASE + 'auth.get_user', side_effect=auth.UserNotFoundError('missing')), patch(
                BASE + 'auth.create_user', side_effect=auth.EmailAlreadyExistsError('exists', None, None)) as create, patch(BASE + 'auth.create_custom_token') as mint:
            with self.assertRaises(naver_auth.HTTPException) as error:
                naver_auth.create_naver_custom_token('naver:stable', 'existing@example.com')
            self.assertEqual(error.exception.status_code, 409)
            self.assertFalse(create.call_args.kwargs['email_verified'])
            mint.assert_not_called()

    def test_missing_email_is_rejected(self):
        tokens = MagicMock(status_code=200)
        tokens.json.return_value = dict(access_token='naver-access')
        profile = MagicMock(status_code=200)
        profile.json.return_value = dict(resultcode='00', response=dict(id='provider-stable-id'))
        with patch(BASE + 'requests.post', return_value=tokens), patch(BASE + 'requests.get', return_value=profile):
            with self.assertRaises(naver_auth.HTTPException) as error:
                naver_auth._provider_identity('code', 'state', dict(client_id=SETTINGS[0], redirect=SETTINGS[2]))
        self.assertEqual(error.exception.status_code, 422)
