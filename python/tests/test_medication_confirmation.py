"""복약 완료 체크의 인증·권한·최초 사용자/시간 유지와 트랜잭션 검증."""
import unittest
from datetime import datetime
from unittest.mock import MagicMock, patch

from fastapi.testclient import TestClient
import pymysql

from python.features.medications.router import get_current_user_id
from python.main import app


class MedicationConfirmationTests(unittest.TestCase):
    def setUp(self):
        self.client = TestClient(app)
        self.addCleanup(self.client.close)
        self.db = MagicMock()
        self.cursor = self.db.cursor.return_value.__enter__.return_value
        self.unconfirmed = {"medication_confirmed_at": None,
                            "confirmed_by_user_id": None, "confirmed_by_name": None}
        self.checked = {"medication_confirmed_at": datetime(2026, 10, 26, 14, 25, 3),
                        "confirmed_by_user_id": "checker-a", "confirmed_by_name": "김가족"}
        self.cursor.fetchone.side_effect = [{"participate_seq": 1}, self.unconfirmed, self.checked]
        app.dependency_overrides[get_current_user_id] = lambda: "checker-a"
        self.addCleanup(app.dependency_overrides.pop, get_current_user_id, None)
        self.connect = self.enterContext(patch("python.features.medications.router.connect", return_value=self.db))

    def confirm(self, payload=None, seq="42"):
        return self.client.post(f"/medications/confirm/{seq}", json=(
            {"family_room_id": "room-a"} if payload is None else payload), headers={"X-User-Id": "forged"})

    def test_active_member_confirms_with_server_user_name_and_database_time(self):
        response = self.confirm()
        self.assertEqual(response.status_code, 200)
        self.assertEqual(response.json(), {
            "result": "OK", "medication_log_seq": 42, "already_confirmed": False,
            "medication_confirmed_at": "2026-10-26T14:25:03",
            "confirmed_by_user_id": "checker-a", "confirmed_by_name": "김가족",
        })
        member, target, update, result = self.cursor.execute.call_args_list
        self.assertEqual(member.args[1], ("room-a", "checker-a"))
        for condition in ("p.is_active = 1", "p.left_at IS NULL", "f.family_room_deleted_at IS NULL",
                          "u.withdrawn_at IS NULL", "FOR UPDATE"):
            self.assertIn(condition, member.args[0])
        # 작성·수정과 달리 체크는 일반 참여자도 허용한다.
        self.assertNotIn("is_representative", member.args[0])
        self.assertEqual(target.args[1], (42, "room-a"))
        self.assertIn("FOR UPDATE", target.args[0])
        self.assertIn("m.record_deleted_at IS NULL", target.args[0])
        self.assertEqual(update.args[1], ("checker-a", 42, "room-a"))
        self.assertIn("medication_confirmed_at = CURRENT_TIMESTAMP", update.args[0])
        self.assertIn("medication_confirmed_at IS NULL", update.args[0])
        self.assertNotIn("record_updated_at", update.args[0])
        self.assertNotIn("SET user_id", update.args[0])
        self.assertIn("checker.name AS confirmed_by_name", result.args[0])
        self.db.commit.assert_called_once()
        self.db.rollback.assert_not_called()
        self.db.close.assert_called_once()

    def test_repeated_or_other_users_check_preserves_first_user_and_time(self):
        original = {**self.checked, "confirmed_by_user_id": "first-checker", "confirmed_by_name": "이가족"}
        self.cursor.fetchone.side_effect = [{"participate_seq": 1}, original]
        response = self.confirm()
        self.assertEqual(response.status_code, 200)
        self.assertTrue(response.json()["already_confirmed"])
        self.assertEqual(response.json()["confirmed_by_user_id"], "first-checker")
        self.assertEqual(response.json()["confirmed_by_name"], "이가족")
        self.assertEqual(response.json()["medication_confirmed_at"], "2026-10-26T14:25:03")
        self.assertEqual(self.cursor.execute.call_count, 2)
        self.db.commit.assert_called_once()

    def test_legacy_confirmed_record_without_user_is_not_overwritten(self):
        self.cursor.fetchone.side_effect = [{"participate_seq": 1}, {
            **self.checked, "confirmed_by_user_id": None, "confirmed_by_name": None}]
        response = self.confirm()
        self.assertTrue(response.json()["already_confirmed"])
        self.assertIsNone(response.json()["confirmed_by_user_id"])
        self.assertEqual(self.cursor.execute.call_count, 2)

    def test_nonmember_missing_deleted_or_other_room_record_cannot_be_checked(self):
        for rows, status, queries in (([None], 403, 1), ([{"participate_seq": 1}, None], 404, 2)):
            with self.subTest(status=status):
                self.db.reset_mock()
                self.cursor.fetchone.side_effect = rows
                self.assertEqual(self.confirm().status_code, status)
                self.assertEqual(self.cursor.execute.call_count, queries)
                self.db.commit.assert_not_called()
                self.db.rollback.assert_called_once()
                self.db.close.assert_called_once()

    def test_unauthenticated_check_never_connects(self):
        app.dependency_overrides.pop(get_current_user_id)
        self.assertEqual(self.confirm().status_code, 401)
        self.connect.assert_not_called()

    def test_user_name_and_time_cannot_be_supplied_by_client(self):
        for payload in ({}, {"family_room_id": " "}, {"family_room_id": "x" * 51},
                        {"family_room_id": "room-a", "user_id": "forged"},
                        {"family_room_id": "room-a", "confirmed_by_user_id": "forged"},
                        {"family_room_id": "room-a", "confirmed_by_name": "위조 이름"},
                        {"family_room_id": "room-a", "medication_confirmed_at": "2026-10-26T12:00:00"}):
            with self.subTest(payload=payload):
                self.assertEqual(self.confirm(payload).status_code, 422)
        for seq in ("0", "-1", "invalid"):
            self.assertEqual(self.confirm(seq=seq).status_code, 422)
        self.connect.assert_not_called()

    def test_database_failure_rolls_back_and_does_not_expose_details(self):
        for stage in ("connect", "member", "target", "update", "read", "commit"):
            with self.subTest(stage=stage):
                self.db.reset_mock()
                self.cursor.fetchone.side_effect = [{"participate_seq": 1}, self.unconfirmed, self.checked]
                self.cursor.execute.side_effect = None
                self.db.commit.side_effect = None
                self.connect.side_effect = None
                error = pymysql.OperationalError(2006, "private database details")
                if stage == "connect":
                    self.connect.side_effect = error
                elif stage == "commit":
                    self.db.commit.side_effect = error
                else:
                    self.cursor.execute.side_effect = [None] * ("member", "target", "update", "read").index(stage) + [error]
                with self.assertLogs("python.features.medications.router", level="ERROR"):
                    response = self.confirm()
                self.assertEqual(response.status_code, 500)
                self.assertNotIn("private database details", response.text)
                if stage != "connect":
                    self.db.rollback.assert_called_once()
                    self.db.close.assert_called_once()

    def test_list_includes_checker_name_and_id(self):
        self.cursor.fetchone.side_effect = [{"participate_seq": 1}]
        self.cursor.fetchall.return_value = [{"medication_log_seq": 42, **self.checked}]
        response = self.client.get("/medications/select?family_room_id=room-a")
        self.assertEqual(response.status_code, 200)
        record = response.json()["results"][0]
        self.assertEqual(record["confirmed_by_name"], "김가족")
        self.assertEqual(record["confirmed_by_user_id"], "checker-a")
        self.assertEqual(record["medication_confirmed_at"], "2026-10-26T14:25:03")
        sql = self.cursor.execute.call_args.args[0]
        self.assertIn("checker.name AS confirmed_by_name", sql)
        self.assertIn("checker.user_id = m.confirmed_by_user_id", sql)


if __name__ == "__main__":
    unittest.main()
