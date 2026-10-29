import unittest
from unittest.mock import MagicMock, patch
from fastapi import FastAPI
from fastapi.testclient import TestClient
from pymysql import OperationalError
from python.features.auth.router import router
from python.features.auth.firebase_auth import require_firebase_user


class ProfileEditTests(unittest.TestCase):
    def setUp(self):
        app = FastAPI()
        app.include_router(router, prefix='/auth')
        app.dependency_overrides[require_firebase_user] = lambda: {'uid': 'verified'}
        self.client = TestClient(app)
        self.addCleanup(self.client.close)
        self.connection = MagicMock()
        self.cursor = self.connection.cursor.return_value.__enter__.return_value
        self.row = dict(user_id='mysql-user', user_email='family@example.com', name='원래 이름', phone='010-1111-2222', withdrawn_at=None)
        self.patch = patch('python.features.auth.router.connect', return_value=self.connection)
        self.patch.start()
        self.addCleanup(self.patch.stop)

    def test_only_verified_profile_changes_and_phone_normalizes(self):
        for phone in ['01012345678', '010-1234-5678']:
            with self.subTest(phone=phone):
                self.cursor.reset_mock()
                updated = {**self.row, 'name': '새 이름', 'phone': '010-1234-5678'}
                self.cursor.fetchone.side_effect = [self.row, updated]
                result = self.client.put('/auth/profile?user_id=another', json={'name': ' 새 이름 ', 'phone': phone})
                self.assertEqual(result.status_code, 200)
                self.assertEqual(result.json()['user']['name'], '새 이름')
                self.assertEqual(result.json()['user']['phone'], '010-1234-5678')
                self.assertEqual(result.json()['user']['user_email'], 'family@example.com')
                self.assertIn('FOR UPDATE', self.cursor.execute.call_args_list[0].args[0])
                sql, params = self.cursor.execute.call_args_list[1].args
                self.assertEqual(params, ('새 이름', '010-1234-5678', 'mysql-user', 'verified', 'verified'))
                self.assertIn('BINARY user_firebase_uid', sql)
                self.assertNotIn('user_email=', sql)
                self.assertNotIn('user_password', sql)
        self.assertEqual(self.connection.commit.call_count, 2)
        self.assertEqual(self.connection.close.call_count, 2)

    def test_same_values_and_zero_changed_rows_are_success(self):
        self.cursor.rowcount = 0
        self.cursor.fetchone.side_effect = [self.row, self.row]
        self.assertEqual(self.client.put('/auth/profile', json={'name': '원래 이름', 'phone': '01011112222'}).status_code, 200)
        self.connection.commit.assert_called_once()

    def test_missing_and_withdrawn_profiles_do_not_update(self):
        for row, status in [(None, 404), ({**self.row, 'withdrawn_at': '2026-10-27'}, 403)]:
            with self.subTest(status=status):
                self.cursor.reset_mock()
                self.cursor.fetchone.return_value = row
                self.assertEqual(self.client.put('/auth/profile', json={'name': '가족', 'phone': '01012345678'}).status_code, status)
                self.assertEqual(self.cursor.execute.call_count, 1)
        self.connection.commit.assert_not_called()
        self.assertEqual(self.connection.rollback.call_count, 2)

    def test_extra_identity_email_and_invalid_input_rejected(self):
        for body in [
            {'name': ' ', 'phone': '01012345678'},
            {'name': '가' * 21, 'phone': '01012345678'},
            {'name': '가족', 'phone': '010-12345678'},
            {'name': '가족', 'phone': '01012345678', 'user_id': 'another'},
            {'name': '가족', 'phone': '01012345678', 'user_email': 'another@example.com'},
        ]:
            self.assertEqual(self.client.put('/auth/profile', json=body).status_code, 422)
        self.cursor.execute.assert_not_called()

    def test_authentication_required(self):
        self.client.app.dependency_overrides.clear()
        self.assertEqual(self.client.put('/auth/profile', json={'name': '가족', 'phone': '01012345678'}).status_code, 401)
        self.cursor.execute.assert_not_called()

    def test_db_failure_rolls_back_and_hides_details(self):
        self.cursor.fetchone.return_value = self.row
        self.cursor.execute.side_effect = [None, OperationalError(2006, 'private')]
        response = self.client.put('/auth/profile', json={'name': '가족', 'phone': '01012345678'})
        self.assertEqual(response.status_code, 503)
        self.assertNotIn('private', response.text)
        self.connection.rollback.assert_called_once()
        self.connection.commit.assert_not_called()
        self.connection.close.assert_called_once()
