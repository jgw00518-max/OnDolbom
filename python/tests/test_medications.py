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

    def create_payload(self, **changes):
        return {
            "family_room_id": "room-a", "medication_info": "테스트 투약 정보",
            "medication_date": "2026-10-23", "medication_time": "아침",
            "dosage_unit": "정", "dosage": "0.500", **changes,
        }

    def test_insert_commits_authenticated_author_and_decimal_dosage(self):
        self.cursor.lastrowid = 42
        with patch("python.features.medications.router.connect", return_value=self.db):
            response = self.client.post("/medications/insert", json=self.create_payload(
                medication_info="  테스트 투약 정보  ",
            ))
        self.assertEqual(response.status_code, 201)
        self.assertEqual(response.json(), {"result": "OK", "medication_log_seq": 42})
        membership, insert = self.cursor.execute.call_args_list
        self.assertEqual(membership.args[1], ("room-a", "verified-user"))
        for condition in ("p.is_active = 1", "p.left_at IS NULL",
                          "f.family_room_deleted_at IS NULL", "u.withdrawn_at IS NULL",
                          "FOR UPDATE"):
            self.assertIn(condition, membership.args[0])
        self.assertEqual(insert.args[1], (
            "room-a", "verified-user", "테스트 투약 정보", date(2026, 10, 23),
            "아침", "정", Decimal("0.500"),
        ))
        self.assertNotIn("medication_confirmed_at", insert.args[0])
        self.db.commit.assert_called_once()
        self.db.rollback.assert_not_called()
        self.db.close.assert_called_once()

    def test_unauthenticated_insert_does_not_connect(self):
        app.dependency_overrides.pop(get_current_user_id)
        with patch("python.features.medications.router.connect") as connect:
            response = self.client.post("/medications/insert", json=self.create_payload())
        self.assertEqual(response.status_code, 401)
        connect.assert_not_called()

    def test_nonmember_cannot_insert(self):
        self.cursor.fetchone.return_value = None
        with patch("python.features.medications.router.connect", return_value=self.db):
            response = self.client.post("/medications/insert", json=self.create_payload())
        self.assertEqual(response.status_code, 403)
        self.assertEqual(self.cursor.execute.call_count, 1)
        self.db.commit.assert_not_called()
        self.db.rollback.assert_called_once()
        self.db.close.assert_called_once()

    def test_insert_rejects_invalid_fields_and_server_managed_values(self):
        invalid = [
            self.create_payload(family_room_id="  "),
            self.create_payload(medication_info="  "),
            self.create_payload(medication_info="가" * 101),
            self.create_payload(medication_date="2026-02-30"),
            self.create_payload(medication_time=""),
            self.create_payload(dosage_unit="정" * 21),
            self.create_payload(dosage="0"), self.create_payload(dosage="-1"),
            self.create_payload(dosage="10000000"),
            self.create_payload(dosage="0.0001"),
            self.create_payload(dosage="NaN"),
            self.create_payload(user_id="forged-author"),
            self.create_payload(medication_confirmed_at="2026-10-23T09:00:00"),
            {key: value for key, value in self.create_payload().items() if key != "medication_date"},
        ]
        for payload in invalid:
            with self.subTest(payload=payload), patch(
                "python.features.medications.router.connect"
            ) as connect:
                response = self.client.post("/medications/insert", json=payload)
                self.assertEqual(response.status_code, 422)
                connect.assert_not_called()

    def test_insert_or_commit_failure_rolls_back(self):
        for stage in ("insert", "commit"):
            with self.subTest(stage=stage):
                self.db.reset_mock()
                self.cursor.execute.side_effect = None
                self.db.commit.side_effect = None
                failure = pymysql.OperationalError(2006, "private database details")
                if stage == "insert":
                    self.cursor.execute.side_effect = [None, failure]
                else:
                    self.db.commit.side_effect = failure
                with patch("python.features.medications.router.connect", return_value=self.db), \
                        self.assertLogs("python.features.medications.router", level="ERROR"):
                    response = self.client.post("/medications/insert", json=self.create_payload())
                self.assertEqual(response.status_code, 500)
                self.assertNotIn("private database details", response.text)
                self.db.rollback.assert_called_once()
                self.db.close.assert_called_once()

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
