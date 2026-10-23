"""실제 DB 없이 투약일지 조회의 접근 권한·날짜·공간 조건을 검증한다."""

import unittest
from datetime import date, datetime
from decimal import Decimal
from unittest.mock import MagicMock, patch

import pymysql
from fastapi.testclient import TestClient

from python.features.medications.router import get_current_user_id
from python.main import app


class MedicationTests(unittest.TestCase):
    def setUp(self):
        self.client = TestClient(app)
        self.db = MagicMock()
        self.cursor = self.db.cursor.return_value.__enter__.return_value
        self.cursor.fetchone.return_value = {"1": 1}
        app.dependency_overrides[get_current_user_id] = lambda: "verified-user"

    def tearDown(self):
        app.dependency_overrides.pop(get_current_user_id, None)
        self.client.close()

    def test_unauthenticated_request_cannot_supply_another_user_id(self):
        app.dependency_overrides.pop(get_current_user_id)
        with patch("python.features.medications.router.connect") as connect:
            response = self.client.get(
                "/medications/select?family_room_id=room-a&user_id=member-b",
                headers={"X-User-Id": "member-b"},
            )
        self.assertEqual(response.status_code, 401)
        connect.assert_not_called()

    def test_nonmember_is_denied_before_log_query(self):
        self.cursor.fetchone.return_value = None
        with patch("python.features.medications.router.connect", return_value=self.db):
            response = self.client.get("/medications/select?family_room_id=room-b")
        self.assertEqual(response.status_code, 403)
        self.assertEqual(self.cursor.execute.call_count, 1)
        self.assertEqual(self.cursor.execute.call_args.args[1], ("room-b", "verified-user"))
        self.db.close.assert_called_once()

    def test_room_logs_serialize_dates_dosage_and_nulls(self):
        self.cursor.fetchall.return_value = [{
            "medication_log_seq": 1, "family_room_id": "room-a", "user_id": "member-b",
            "medication_info": "테스트 투약 정보", "medication_date": date(2026, 10, 23),
            "medication_time": "아침", "dosage_unit": "정", "dosage": Decimal("0.500"),
            "medication_confirmed_at": None, "recorded_at": datetime(2026, 10, 23, 8),
            "record_updated_at": None,
        }]
        with patch("python.features.medications.router.connect", return_value=self.db):
            response = self.client.get(
                "/medications/select?family_room_id=room-a&limit=10&offset=20"
            )
        self.assertEqual(response.status_code, 200)
        row = response.json()["results"][0]
        self.assertEqual(row["medication_date"], "2026-10-23")
        self.assertEqual(row["recorded_at"], "2026-10-23T08:00:00")
        self.assertEqual(row["dosage"], 0.5)
        self.assertIsNone(row["medication_confirmed_at"])
        self.assertEqual(self.cursor.execute.call_args.args[1], ("room-a", 10, 20))
        sql = self.cursor.execute.call_args.args[0]
        for condition in ("m.family_room_id = %s", "m.record_deleted_at IS NULL",
                          "f.family_room_deleted_at IS NULL"):
            self.assertIn(condition, sql)
        self.db.close.assert_called_once()

    def test_filter_uses_typed_date_and_parameter_binding(self):
        self.cursor.fetchall.return_value = []
        with patch("python.features.medications.router.connect", return_value=self.db):
            response = self.client.get(
                "/medications/select?family_room_id=room-a&medication_date=2026-10-23"
            )
        self.assertEqual(response.status_code, 200)
        self.assertIn("m.medication_date = %s", self.cursor.execute.call_args.args[0])
        self.assertEqual(
            self.cursor.execute.call_args.args[1], ("room-a", date(2026, 10, 23), 20, 0)
        )

    def test_no_logs_returns_empty_list(self):
        self.cursor.fetchall.return_value = []
        with patch("python.features.medications.router.connect", return_value=self.db):
            response = self.client.get("/medications/select?family_room_id=room-a")
        self.assertEqual(response.status_code, 200)
        self.assertEqual(response.json(), {"results": []})

    def test_invalid_parameters_do_not_connect(self):
        for query in ("", "family_room_id=", "family_room_id=room-a&medication_date=invalid",
                      "family_room_id=room-a&limit=0", "family_room_id=room-a&limit=101",
                      "family_room_id=room-a&offset=-1"):
            with self.subTest(query=query), patch(
                "python.features.medications.router.connect"
            ) as connect:
                response = self.client.get(f"/medications/select?{query}")
                self.assertEqual(response.status_code, 422)
                connect.assert_not_called()

    def test_query_failure_hides_details_and_closes_connection(self):
        self.cursor.execute.side_effect = pymysql.OperationalError(2006, "private SQL details")
        with patch("python.features.medications.router.connect", return_value=self.db), \
                self.assertLogs("python.features.medications.router", level="ERROR"):
            response = self.client.get("/medications/select?family_room_id=room-a")
        self.assertEqual(response.status_code, 500)
        self.assertNotIn("private SQL details", response.text)
        self.db.close.assert_called_once()


if __name__ == "__main__":
    unittest.main()
