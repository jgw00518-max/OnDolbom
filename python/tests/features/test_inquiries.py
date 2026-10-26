"""실제 DB를 변경하지 않고 문의 인증·소유자 경계·저장을 검증한다."""
import unittest
from unittest.mock import MagicMock, patch

from fastapi import FastAPI
from fastapi.testclient import TestClient
from pymysql import OperationalError
from python.features.auth.firebase_auth import require_firebase_user
from python.features.inquiries.router import router


class InquiryTests(unittest.TestCase):
    def setUp(self):
        app = FastAPI()
        app.include_router(router)
        app.dependency_overrides[require_firebase_user] = lambda: {"uid": "verified-uid"}
        self.client = TestClient(app)
        self.connection = MagicMock()
        self.cursor = self.connection.cursor.return_value.__enter__.return_value
        self.cursor.fetchone.return_value = {"user_id": "owner", "withdrawn_at": None}
        self.cursor.fetchall.return_value = []
        self.cursor.lastrowid = 42
        self.patch = patch('python.features.inquiries.router.connect', return_value=self.connection)
        self.patch.start()
        self.addCleanup(self.patch.stop)
        self.addCleanup(self.client.close)

    def test_create_without_room_uses_verified_owner_and_commits(self):
        response = self.client.post('/inquiries', json={"question_title": " title ", "question_content": " content "})
        self.assertEqual(response.status_code, 201)
        self.assertEqual(response.json(), {"question_seq": 42})
        self.assertEqual(self.cursor.execute.call_args.args[1], ("owner", None, "title", "content"))
        self.connection.commit.assert_called_once()
        self.connection.close.assert_called_once()

    def test_client_cannot_spoof_user_or_send_blank_emoji(self):
        for body in (
            {"question_title": "title", "question_content": "content", "user_id": "other"},
            {"question_title": "  ", "question_content": "content"},
            {"question_title": "title", "question_content": "\U0001f600"},
        ):
            self.assertEqual(self.client.post('/inquiries', json=body).status_code, 422)
        self.connection.commit.assert_not_called()

    def test_room_requires_active_membership(self):
        self.cursor.fetchone.side_effect = [{"user_id": "owner", "withdrawn_at": None}, None]
        response = self.client.post('/inquiries', json={"question_title": "title", "question_content": "content", "family_room_id": "other-room"})
        self.assertEqual(response.status_code, 403)
        self.assertIn('p.left_at IS NULL', self.cursor.execute.call_args.args[0])
        self.assertIn('f.family_room_deleted_at IS NULL', self.cursor.execute.call_args.args[0])
        self.connection.rollback.assert_called_once()
        self.connection.commit.assert_not_called()

    def test_room_inquiry_stores_authorized_room(self):
        self.cursor.fetchone.side_effect = [{"user_id": "owner", "withdrawn_at": None}, {"participate_seq": 1}]
        response = self.client.post('/inquiries', json={"question_title": "title", "question_content": "content", "family_room_id": "my-room"})
        self.assertEqual(response.status_code, 201)
        self.assertEqual(self.cursor.execute.call_args.args[1], ("owner", "my-room", "title", "content"))

    def test_list_filters_owner_and_deleted_and_paginates(self):
        self.cursor.fetchall.return_value = [{"question_seq": 100-i} for i in range(51)]
        response = self.client.get('/inquiries?before_seq=200')
        self.assertEqual(response.status_code, 200)
        self.assertEqual(len(response.json()['items']), 50)
        self.assertEqual(response.json()['next_cursor'], 51)
        sql, params = self.cursor.execute.call_args.args
        self.assertIn('q.user_id = %s', sql)
        self.assertIn('q.question_deleted_at IS NULL', sql)
        self.assertEqual(params, ['owner', 200])

    def test_other_user_or_deleted_inquiry_is_404_before_answers(self):
        self.cursor.fetchone.side_effect = [{"user_id": "owner", "withdrawn_at": None}, None]
        self.assertEqual(self.client.get('/inquiries/99').status_code, 404)
        self.assertEqual(self.cursor.execute.call_count, 2)
        self.assertEqual(self.cursor.execute.call_args.args[1], (99, "owner"))

    def test_detail_reads_only_non_deleted_answers_for_owner(self):
        self.cursor.fetchone.side_effect = [{"user_id": "owner", "withdrawn_at": None}, {"question_seq": 42}]
        self.cursor.fetchall.return_value = [{"answer_seq": 1, "answer_content": "reply"}]
        response = self.client.get('/inquiries/42')
        self.assertEqual(response.status_code, 200)
        self.assertTrue(response.json()['answered'])
        self.assertIn('answer_deleted_at IS NULL', self.cursor.execute.call_args.args[0])
        self.assertEqual(self.cursor.execute.call_args.args[1], (42, "owner"))

    def test_withdrawn_or_unregistered_user_is_forbidden(self):
        for row in (None, {"user_id": "owner", "withdrawn_at": "date"}):
            self.cursor.fetchone.return_value = row
            self.assertEqual(self.client.get('/inquiries').status_code, 403)

    def test_db_failure_rolls_back_without_exposing_details(self):
        self.cursor.execute.side_effect = OperationalError(2006, 'private database details')
        response = self.client.post('/inquiries', json={"question_title": "title", "question_content": "content"})
        self.assertEqual(response.status_code, 503)
        self.assertNotIn('private database details', response.text)
        self.connection.rollback.assert_called_once()
        self.connection.close.assert_called_once()

    def test_missing_token_rejected_before_db(self):
        self.client.app.dependency_overrides.clear()
        self.assertEqual(self.client.get('/inquiries').status_code, 401)
        self.cursor.execute.assert_not_called()
