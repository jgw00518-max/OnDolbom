"""체크 해제의 현재 권한·낙관적 충돌 검사·트랜잭션을 검증한다."""
import unittest
from datetime import datetime, timedelta
from unittest.mock import MagicMock, patch

from fastapi.testclient import TestClient
import pymysql

from python.features.medications.router import get_current_user_id
from python.main import app


class MedicationUnconfirmationTests(unittest.TestCase):
    def setUp(self):
        self.client = TestClient(app)
        self.addCleanup(self.client.close)
        self.db = MagicMock()
        self.cursor = self.db.cursor.return_value.__enter__.return_value
        self.member = {"participate_seq": 1, "is_representative": 0}
        self.checked = {"medication_confirmed_at": datetime(2026, 10, 26, 14, 25, 3),
                        "confirmed_by_user_id": "checker-a"}
        self.payload = {"family_room_id": "room-a",
                        "expected_confirmed_at": "2026-10-26T14:25:03",
                        "expected_confirmed_by_user_id": "checker-a"}
        self.cursor.fetchone.side_effect = [self.member, self.checked]
        app.dependency_overrides[get_current_user_id] = lambda: "checker-a"
        self.addCleanup(app.dependency_overrides.pop, get_current_user_id, None)
        self.connect = self.enterContext(patch(
            "python.features.medications.router.connect", return_value=self.db))

    def unconfirm(self, payload=None, seq="42"):
        return self.client.request("DELETE", f"/medications/confirm/{seq}",
                                   json=self.payload if payload is None else payload,
                                   headers={"X-User-Id": "forged"})

    def test_checker_can_clear_confirmation_without_changing_author_or_content(self):
        response = self.unconfirm()
        self.assertEqual(response.status_code, 200)
        self.assertEqual(response.json(), {
            "result": "OK", "medication_log_seq": 42, "already_unconfirmed": False,
            "medication_confirmed_at": None, "confirmed_by_user_id": None,
            "confirmed_by_name": None,
        })
        member, target, update = self.cursor.execute.call_args_list
        self.assertEqual(member.args[1], ("room-a", "checker-a"))
        for condition in ("p.is_active = 1", "p.left_at IS NULL", "p.is_representative",
                          "f.family_room_deleted_at IS NULL", "u.withdrawn_at IS NULL", "FOR UPDATE"):
            self.assertIn(condition, member.args[0])
        self.assertIn("FOR UPDATE", target.args[0])
        self.assertIn("record_deleted_at IS NULL", target.args[0])
        self.assertEqual(target.args[1], (42, "room-a"))
        self.assertEqual(update.args[1], (42, "room-a"))
        self.assertIn("SET medication_confirmed_at = NULL, confirmed_by_user_id = NULL", update.args[0])
        self.assertNotIn("record_updated_at", update.args[0])
        self.assertNotIn("SET user_id", update.args[0])
        self.db.commit.assert_called_once()
        self.db.rollback.assert_not_called()
        self.db.close.assert_called_once()

    def test_current_representative_can_clear_another_or_legacy_confirmation(self):
        for checker in ("other-user", None):
            with self.subTest(checker=checker):
                self.cursor.fetchone.side_effect = [
                    {**self.member, "is_representative": 1},
                    {**self.checked, "confirmed_by_user_id": checker}]
                response = self.unconfirm({**self.payload, "expected_confirmed_by_user_id": checker})
                self.assertEqual(response.status_code, 200)
                self.assertFalse(response.json()["already_unconfirmed"])

    def test_other_member_or_former_representative_cannot_clear_other_or_legacy_check(self):
        for checker in ("other-user", None):
            with self.subTest(checker=checker):
                self.db.reset_mock()
                self.cursor.fetchone.side_effect = [self.member, {
                    **self.checked, "confirmed_by_user_id": checker}]
                self.assertEqual(self.unconfirm().status_code, 403)
                self.assertEqual(self.cursor.execute.call_count, 2)
                self.db.rollback.assert_called_once()
                self.db.commit.assert_not_called()

    def test_inactive_nonmember_and_missing_deleted_or_other_room_record(self):
        for rows, status, queries in (([None], 403, 1), ([self.member, None], 404, 2)):
            with self.subTest(status=status):
                self.db.reset_mock()
                self.cursor.fetchone.side_effect = rows
                self.assertEqual(self.unconfirm().status_code, status)
                self.assertEqual(self.cursor.execute.call_count, queries)
                self.db.rollback.assert_called_once()
                self.db.commit.assert_not_called()
                self.db.close.assert_called_once()

    def test_repeated_clear_is_success_without_writing(self):
        self.cursor.fetchone.side_effect = [self.member, {
            "medication_confirmed_at": None, "confirmed_by_user_id": None}]
        response = self.unconfirm()
        self.assertEqual(response.status_code, 200)
        self.assertTrue(response.json()["already_unconfirmed"])
        self.assertEqual(self.cursor.execute.call_count, 2)
        self.db.commit.assert_called_once()

    def test_stale_time_or_checker_cannot_remove_new_check_even_for_representative(self):
        for changed in ({"medication_confirmed_at": self.checked["medication_confirmed_at"] + timedelta(seconds=1)},
                        {"confirmed_by_user_id": "new-checker"}):
            with self.subTest(changed=changed):
                self.db.reset_mock()
                self.cursor.fetchone.side_effect = [
                    {**self.member, "is_representative": 1}, {**self.checked, **changed}]
                self.assertEqual(self.unconfirm().status_code, 409)
                self.assertEqual(self.cursor.execute.call_count, 2)
                self.db.rollback.assert_called_once()
                self.db.commit.assert_not_called()

    def test_unauthenticated_request_never_connects(self):
        app.dependency_overrides.pop(get_current_user_id)
        self.assertEqual(self.unconfirm().status_code, 401)
        self.connect.assert_not_called()

    def test_invalid_or_forged_input_never_connects(self):
        for payload in ({}, {**self.payload, "family_room_id": " "},
                        {**self.payload, "family_room_id": "x" * 51},
                        {**self.payload, "expected_confirmed_at": None},
                        {**self.payload, "expected_confirmed_at": "invalid"},
                        {**self.payload, "expected_confirmed_at": "2026-10-26T14:25:03Z"},
                        {**self.payload, "expected_confirmed_by_user_id": " "},
                        {**self.payload, "is_representative": True},
                        {**self.payload, "user_id": "forged"}):
            with self.subTest(payload=payload):
                self.assertEqual(self.unconfirm(payload).status_code, 422)
        for field in ("expected_confirmed_at", "expected_confirmed_by_user_id"):
            payload = self.payload.copy()
            del payload[field]
            self.assertEqual(self.unconfirm(payload).status_code, 422)
        for seq in ("0", "-1", "invalid"):
            self.assertEqual(self.unconfirm(seq=seq).status_code, 422)
        self.connect.assert_not_called()

    def test_database_failure_rolls_back_and_hides_details(self):
        for stage in ("connect", "member", "target", "update", "commit"):
            with self.subTest(stage=stage):
                self.db.reset_mock()
                self.cursor.fetchone.side_effect = [self.member, self.checked]
                self.cursor.execute.side_effect = None
                self.db.commit.side_effect = None
                self.connect.side_effect = None
                error = pymysql.OperationalError(2006, "private database details")
                if stage == "connect":
                    self.connect.side_effect = error
                elif stage == "commit":
                    self.db.commit.side_effect = error
                else:
                    self.cursor.execute.side_effect = [None] * ("member", "target", "update").index(stage) + [error]
                with self.assertLogs("python.features.medications.router", level="ERROR"):
                    response = self.unconfirm()
                self.assertEqual(response.status_code, 500)
                self.assertNotIn("private database details", response.text)
                if stage != "connect":
                    self.db.rollback.assert_called_once()
                    self.db.close.assert_called_once()


if __name__ == "__main__":
    unittest.main()
