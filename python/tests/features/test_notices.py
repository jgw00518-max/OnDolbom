import unittest
from unittest.mock import MagicMock, patch
from fastapi import FastAPI
from fastapi.testclient import TestClient
from pymysql import OperationalError
from python.features.auth.firebase_auth import require_firebase_user
from python.features.notices.router import router


class NoticeTests(unittest.TestCase):
    def setUp(self):
        app = FastAPI()
        app.include_router(router)
        app.dependency_overrides[require_firebase_user] = lambda: {'uid': 'family'}
        self.client = TestClient(app)
        self.connection = MagicMock()
        self.cursor = self.connection.cursor.return_value.__enter__.return_value
        self.patch = patch('python.features.notices.router.connect', return_value=self.connection)
        self.patch.start()
        self.addCleanup(self.patch.stop)

    def test_list_uses_admin_contract_and_hides_deleted(self):
        self.cursor.fetchall.return_value = [{'notice_id': str(i)} for i in range(31)]
        response = self.client.get('/notices?offset=30')
        self.assertEqual(len(response.json()['items']), 30)
        self.assertTrue(response.json()['has_more'])
        self.assertIn('notice_deleted_at IS NULL', self.cursor.execute.call_args.args[0])
        self.assertEqual(self.cursor.execute.call_args.args[1], (31, 30))
        self.connection.close.assert_called_once()

    def test_detail_uses_both_keys_and_not_found(self):
        self.cursor.fetchone.return_value = {'notice_id': 'notice', 'admin_id': 'admin'}
        self.assertEqual(self.client.get('/notices/admin/notice').status_code, 200)
        self.assertEqual(self.cursor.execute.call_args.args[1], ('admin', 'notice'))
        self.cursor.fetchone.return_value = None
        self.assertEqual(self.client.get('/notices/admin/notice').status_code, 404)

    def test_missing_auth_and_write_rejected(self):
        self.client.app.dependency_overrides.clear()
        self.assertEqual(self.client.get('/notices').status_code, 401)
        self.assertEqual(self.client.post('/notices', json={}).status_code, 405)
        self.cursor.execute.assert_not_called()

    def test_db_error_is_sanitized(self):
        self.cursor.execute.side_effect = OperationalError(2006, 'private')
        result = self.client.get('/notices')
        self.assertEqual(result.status_code, 503)
        self.assertNotIn('private', result.text)
