"""Firebase 인증부터 기능 라우터의 사용자·공간 권한까지 모의 객체로 검증한다."""
import unittest
from itertools import cycle
from unittest.mock import MagicMock, patch

from firebase_admin import auth
from fastapi.testclient import TestClient
from pymysql import OperationalError

from python.main import app


class AuthTests(unittest.TestCase):
    def setUp(self):
        self.client = TestClient(app)
        self.auth_db = MagicMock()
        self.auth_cursor = self.auth_db.cursor.return_value.__enter__.return_value
        self.auth_cursor.fetchone.return_value = {'user_id': 'db-user', 'withdrawn_at': None}
        self.feature_db = MagicMock()
        self.cursor = self.feature_db.cursor.return_value.__enter__.return_value
        self.cursor.fetchone.return_value = {'participate_seq': 1}
        self.cursor.fetchall.return_value = []
        self.cursor.lastrowid = 42
        self.verify = self.enterContext(patch(
            'python.features.auth.firebase_auth.auth.verify_id_token',
            return_value={'uid': 'verified-UID'}))
        self.enterContext(patch('python.features.auth.firebase_auth.get_firebase_app', return_value='app'))
        self.memo_connect = self.enterContext(patch('python.features.memos.router.connect', side_effect=cycle((self.auth_db, self.feature_db))))
        self.med_connect = self.enterContext(patch('python.features.medications.router.connect', side_effect=cycle((self.auth_db, self.feature_db))))
        self.addCleanup(self.client.close)

    def requests(self, header='Bearer valid-token'):
        headers = {'X-User-Id': 'forged'}
        if header is not None:
            headers['Authorization'] = header
        yield self.client.get('/memos/select?family_room_id=room-a&user_id=forged', headers=headers)
        yield self.client.post('/memos/insert', headers=headers, json={
            'family_room_id': 'room-a', 'memo_content': '메모', 'user_id': 'forged'})
        yield self.client.get('/medications/select?family_room_id=room-a', headers=headers)
        yield self.client.post('/medications/insert', headers=headers, json={
            'family_room_id': 'room-a', 'medication_info': '약',
            'medication_date': '2026-10-24', 'medication_time': '아침',
            'dosage_unit': '정', 'dosage': '1'})

    def test_verified_uid_maps_to_internal_author_for_all_routes(self):
        self.assertEqual([r.status_code for r in self.requests()], [200, 201, 200, 201])
        for call in self.verify.call_args_list:
            self.assertEqual(call.args, ('valid-token',))
            self.assertTrue(call.kwargs['check_revoked'])
        for call in self.auth_cursor.execute.call_args_list:
            self.assertIn('BINARY user_firebase_uid', call.args[0])
            self.assertEqual(call.args[1], ('verified-UID', 'verified-UID'))
        for call in self.cursor.execute.call_args_list:
            sql, values = call.args
            if 'participate AS p' in sql:
                self.assertEqual(values, ('room-a', 'db-user'))
            elif 'INSERT INTO' in sql:
                self.assertIn('db-user', values)
                self.assertNotIn('forged', values)
        self.assertEqual(self.auth_db.close.call_count, 4)
        self.assertEqual(self.feature_db.commit.call_count, 2)

    def test_missing_or_wrong_scheme_never_reaches_database(self):
        for header in (None, 'Basic forged'):
            self.assertEqual([r.status_code for r in self.requests(header)], [401] * 4)
        self.verify.assert_not_called()
        self.memo_connect.assert_not_called()
        self.med_connect.assert_not_called()

    def test_invalid_expired_and_revoked_tokens_are_rejected(self):
        for error in (auth.InvalidIdTokenError('private'),
                      auth.ExpiredIdTokenError('private', cause=None),
                      auth.RevokedIdTokenError('private')):
            self.verify.side_effect = error
            for response in self.requests('Bearer forged'):
                self.assertEqual(response.status_code, 401)
                self.assertNotIn('private', response.text)
        self.memo_connect.assert_not_called()
        self.med_connect.assert_not_called()

    def test_unregistered_and_withdrawn_accounts_are_forbidden(self):
        self.memo_connect.side_effect = lambda: self.auth_db
        self.med_connect.side_effect = lambda: self.auth_db
        for row in (None, {'user_id': 'db-user', 'withdrawn_at': '2026-10-24'}):
            self.auth_cursor.fetchone.return_value = row
            self.assertEqual([r.status_code for r in self.requests()], [403] * 4)
        self.cursor.execute.assert_not_called()

    def test_verified_nonmember_is_forbidden(self):
        self.cursor.fetchone.return_value = None
        self.assertEqual([r.status_code for r in self.requests()], [403] * 4)
        self.feature_db.commit.assert_not_called()

    def test_database_failure_closes_connection_and_hides_details(self):
        self.memo_connect.side_effect = lambda: self.auth_db
        self.med_connect.side_effect = lambda: self.auth_db
        self.auth_cursor.execute.side_effect = OperationalError(2006, 'private')
        for response in self.requests():
            self.assertEqual(response.status_code, 503)
            self.assertNotIn('private', response.text)
        self.assertEqual(self.auth_db.close.call_count, 4)
        self.cursor.execute.assert_not_called()


if __name__ == '__main__':
    unittest.main()
