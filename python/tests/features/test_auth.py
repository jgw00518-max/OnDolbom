# Firebase·DB를 대체한 API 테스트다. 실제 인증이나 DB 동시성 검증과는 구분한다.
import unittest
from unittest.mock import MagicMock, patch

from fastapi import HTTPException
from fastapi.testclient import TestClient
from firebase_admin import auth
from pymysql import IntegrityError

from python.features.auth.firebase_auth import require_firebase_user, verify_firebase_token, get_firebase_app
from python.main import app


class AuthTests(unittest.TestCase):
    def setUp(self):
        self.client = TestClient(app)

    def tearDown(self):
        app.dependency_overrides.clear()
        self.client.close()

    def test_missing_and_wrong_scheme_rejected_before_db(self):
        with patch('python.features.auth.router.connect') as connect:
            for headers in ({}, {'Authorization': 'Basic abc'}):
                self.assertEqual(self.client.get('/auth/me', headers=headers).status_code, 401)
            connect.assert_not_called()

    def test_invalid_token_rejected_before_db(self):
        with patch('python.features.auth.firebase_auth.get_firebase_app', return_value=object()), patch(
            'python.features.auth.firebase_auth.auth.verify_id_token', side_effect=auth.InvalidIdTokenError('private')
        ), patch('python.features.auth.router.connect') as connect:
            response = self.client.get('/auth/me', headers={'Authorization': 'Bearer invalid'})
            self.assertEqual(response.status_code, 401)
            self.assertNotIn('private', response.text)
            connect.assert_not_called()

    def test_verification_checks_revocation(self):
        firebase_app = object()
        with patch('python.features.auth.firebase_auth.get_firebase_app', return_value=firebase_app), patch(
            'python.features.auth.firebase_auth.auth.verify_id_token', return_value={'uid': 'verified-uid'}
        ) as verify:
            self.assertEqual(verify_firebase_token('test-token')['uid'], 'verified-uid')
            verify.assert_called_once_with('test-token', app=firebase_app, check_revoked=True)

    def test_missing_server_credentials_returns_503(self):
        with patch('python.features.auth.firebase_auth.firebase_admin.get_app', side_effect=ValueError), patch(
            'python.features.auth.firebase_auth.dotenv_values', return_value={}
        ), patch.dict('os.environ', {}, clear=True):
            with self.assertRaises(HTTPException) as context:
                get_firebase_app()
            self.assertEqual(context.exception.status_code, 503)

    def query_profile(self, row):
        app.dependency_overrides[require_firebase_user] = lambda: {'uid': 'verified-uid'}
        connection = MagicMock()
        cursor = connection.cursor.return_value.__enter__.return_value
        cursor.fetchone.return_value = row
        with patch('python.features.auth.router.connect', return_value=connection):
            response = self.client.get('/auth/me?uid=attacker')
        self.assertEqual(cursor.execute.call_args.args[1], ('verified-uid', 'verified-uid'))
        self.assertIn('BINARY user_firebase_uid', cursor.execute.call_args.args[0])
        connection.close.assert_called_once()
        connection.commit.assert_not_called()
        return response

    def test_unregistered_profile(self):
        response = self.query_profile(None)
        self.assertEqual(response.json(), {'registered': False, 'user': None})

    def test_registered_profile_only_returns_public_fields(self):
        row = dict(user_id='local-id', user_email='family@example.com', name='가족', phone='010', withdrawn_at=None)
        response = self.query_profile(row)
        self.assertEqual(response.status_code, 200)
        self.assertTrue(response.json()['registered'])
        self.assertNotIn('withdrawn_at', response.json()['user'])

    def test_withdrawn_profile_forbidden(self):
        row = dict(user_id='local-id', user_email=None, name=None, phone=None, withdrawn_at='2026-10-23')
        self.assertEqual(self.query_profile(row).status_code, 403)

    def test_db_failure_is_not_an_unregistered_profile(self):
        app.dependency_overrides[require_firebase_user] = lambda: {'uid': 'verified-uid'}
        with patch('python.features.auth.router.connect', side_effect=ValueError('private config')):
            response = self.client.get('/auth/me')
        self.assertEqual(response.status_code, 503)
        self.assertNotIn('private', response.text)

    def registration(self, results, phone='01012345678', insert_error=None):
        # SELECT 결과와 INSERT 충돌을 조절해 최초 등록·재요청·실패 분기를 재현한다.
        app.dependency_overrides[require_firebase_user] = lambda: {'uid': 'verified-uid', 'email': 'verified@example.com'}
        connection = MagicMock()
        cursor = connection.cursor.return_value.__enter__.return_value
        cursor.fetchone.side_effect = results
        if insert_error:
            def execute(sql, params):
                if 'INSERT INTO' in sql:
                    raise insert_error
            cursor.execute.side_effect = execute
        with patch('python.features.auth.router.connect', return_value=connection):
            response = self.client.post('/auth/profile', json={'name': ' 가족 ', 'phone': phone})
        connection.close.assert_called_once()
        return response, connection, cursor

    def test_register_normalizes_phone_and_uses_verified_identity(self):
        from uuid import UUID
        row = dict(user_id='local-id', user_email='verified@example.com', name='가족', phone='010-1234-5678', withdrawn_at=None)
        for phone in ('01012345678', '010-1234-5678'):
            with self.subTest(phone=phone):
                response, connection, cursor = self.registration([None, row], phone)
                self.assertEqual(response.status_code, 200)
                insert = next(call for call in cursor.execute.call_args_list if 'INSERT INTO' in call.args[0])
                params = insert.args[1]
                UUID(params[0])
                self.assertEqual(params[1:], ('verified-uid', 'verified@example.com', '가족', '010-1234-5678'))
                self.assertNotIn('user_password', insert.args[0])
                connection.commit.assert_called_once()

    def test_repeat_registration_does_not_insert_or_overwrite(self):
        row = dict(user_id='existing', user_email='verified@example.com', name='기존', phone='010-1111-2222', withdrawn_at=None)
        response, connection, cursor = self.registration([row])
        self.assertEqual(response.json()['user']['name'], '기존')
        self.assertFalse(any('INSERT' in call.args[0] for call in cursor.execute.call_args_list))
        connection.commit.assert_not_called()

    def test_concurrent_registration_unique_conflict_returns_same_user(self):
        row = dict(user_id='existing', user_email=None, name='가족', phone='010-1234-5678', withdrawn_at=None)
        response, connection, _ = self.registration([None, row], insert_error=IntegrityError(1062, 'duplicate'))
        self.assertEqual(response.status_code, 200)
        self.assertEqual(response.json()['user']['user_id'], 'existing')
        connection.rollback.assert_called_once()
        connection.commit.assert_not_called()

    def test_uid_case_collision_does_not_return_another_user(self):
        response, connection, _ = self.registration([None, None], insert_error=IntegrityError(1062, 'duplicate'))
        self.assertEqual(response.status_code, 409)
        connection.commit.assert_not_called()

    def test_profile_fields_required_and_identity_cannot_be_injected(self):
        app.dependency_overrides[require_firebase_user] = lambda: {'uid': 'verified-uid'}
        invalid = [
            {}, {'name': ' ', 'phone': '01012345678'},
            {'name': '가' * 21, 'phone': '01012345678'},
            {'name': '가족', 'phone': ''}, {'name': '가족', 'phone': '010-12345678'},
            {'name': '가족', 'phone': '01012345678', 'user_firebase_uid': 'attacker'},
        ]
        with patch('python.features.auth.router.connect') as connect:
            for payload in invalid:
                with self.subTest(payload=payload):
                    self.assertEqual(self.client.post('/auth/profile', json=payload).status_code, 422)
            connect.assert_not_called()

    def test_failed_insert_rolls_back(self):
        response, connection, _ = self.registration([None], insert_error=IntegrityError(1048, 'private'))
        self.assertEqual(response.status_code, 503)
        self.assertNotIn('private', response.text)
        connection.rollback.assert_called_once()
