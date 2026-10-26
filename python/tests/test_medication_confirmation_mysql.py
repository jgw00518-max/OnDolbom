"""명시적 ONDOLBOM_MYSQL_TESTS=1 실행 시 임시 투약 기록으로 동시 체크 검증."""
from concurrent.futures import ThreadPoolExecutor
import os
import unittest
from uuid import uuid4

from python.database import connect
from python.features.medications.router import (
    MedicationConfirm, MedicationUnconfirm, confirm_medication,
    select_medications, unconfirm_medication,
)


@unittest.skipUnless(os.environ.get("ONDOLBOM_MYSQL_TESTS") == "1", "explicit MySQL test opt-in required")
class MedicationConfirmationMySQLTests(unittest.TestCase):
    def setUp(self):
        conn = connect()
        try:
            with conn.cursor() as cursor:
                cursor.execute("""SELECT p.family_room_id, p.user_id, u.name FROM participate AS p
                    JOIN family_room AS f ON f.family_room_id = p.family_room_id
                    JOIN `user` AS u ON u.user_id = p.user_id
                    WHERE p.is_active = 1 AND p.left_at IS NULL
                      AND f.family_room_deleted_at IS NULL AND u.withdrawn_at IS NULL
                    ORDER BY p.is_representative ASC LIMIT 1""")
                member = cursor.fetchone()
                if member is None:
                    self.skipTest("active room member required for temporary fixture")
                self.room_id, self.user_id, self.name = member["family_room_id"], member["user_id"], member["name"]
                self.marker = "confirmation-test-" + str(uuid4())
                cursor.execute("""INSERT INTO medication_log
                    (family_room_id, user_id, medication_info, medication_date, medication_time, dosage_unit, dosage)
                    VALUES (%s, %s, %s, CURRENT_DATE, 'test', 'test', 1)""",
                               (self.room_id, self.user_id, self.marker))
                self.seq = cursor.lastrowid
            conn.commit()
        finally:
            conn.close()
        self.addCleanup(self.clean_fixture)

    def clean_fixture(self):
        conn = connect()
        try:
            with conn.cursor() as cursor:
                cursor.execute("""DELETE FROM medication_log
                    WHERE medication_log_seq = %s AND family_room_id = %s AND medication_info = %s""",
                               (self.seq, self.room_id, self.marker))
            conn.commit()
        finally:
            conn.close()

    def test_concurrent_unchecks_clear_once_and_allow_rechecking(self):
        confirmed = confirm_medication(MedicationConfirm(family_room_id=self.room_id), self.seq, self.user_id)
        data = MedicationUnconfirm(
            family_room_id=self.room_id,
            expected_confirmed_at=confirmed["medication_confirmed_at"],
            expected_confirmed_by_user_id=self.user_id,
        )
        with ThreadPoolExecutor(max_workers=4) as pool:
            responses = list(pool.map(lambda _: unconfirm_medication(data, self.seq, self.user_id), range(8)))
        self.assertEqual(sum(not result["already_unconfirmed"] for result in responses), 1)
        for result in responses:
            self.assertIsNone(result["medication_confirmed_at"])
            self.assertIsNone(result["confirmed_by_user_id"])
            self.assertIsNone(result["confirmed_by_name"])
        conn = connect()
        try:
            with conn.cursor() as cursor:
                cursor.execute("""SELECT user_id, medication_confirmed_at, confirmed_by_user_id
                    FROM medication_log WHERE medication_log_seq = %s""", (self.seq,))
                row = cursor.fetchone()
                self.assertEqual(row["user_id"], self.user_id)
                self.assertIsNone(row["medication_confirmed_at"])
                self.assertIsNone(row["confirmed_by_user_id"])
        finally:
            conn.close()
        rechecked = confirm_medication(MedicationConfirm(family_room_id=self.room_id), self.seq, self.user_id)
        self.assertFalse(rechecked["already_confirmed"])
        self.assertEqual(rechecked["confirmed_by_user_id"], self.user_id)

    def test_concurrent_checks_keep_first_checker_name_time_and_original_author(self):
        data = MedicationConfirm(family_room_id=self.room_id)
        with ThreadPoolExecutor(max_workers=4) as pool:
            responses = list(pool.map(lambda _: confirm_medication(data, self.seq, self.user_id), range(8)))
        self.assertEqual(sum(not result["already_confirmed"] for result in responses), 1)
        first_time = responses[0]["medication_confirmed_at"]
        self.assertIsNotNone(first_time)
        for result in responses:
            self.assertEqual(result["medication_confirmed_at"], first_time)
            self.assertEqual(result["confirmed_by_user_id"], self.user_id)
            self.assertEqual(result["confirmed_by_name"], self.name)
        conn = connect()
        try:
            with conn.cursor() as cursor:
                cursor.execute("SELECT user_id FROM medication_log WHERE medication_log_seq = %s", (self.seq,))
                self.assertEqual(cursor.fetchone()["user_id"], self.user_id)
                cursor.execute("""SELECT user_id FROM participate WHERE family_room_id = %s
                    AND user_id <> %s AND is_active = 1 AND left_at IS NULL LIMIT 1""", (self.room_id, self.user_id))
                other = cursor.fetchone()
        finally:
            conn.close()
        if other is not None:
            result = confirm_medication(data, self.seq, other["user_id"])
            self.assertTrue(result["already_confirmed"])
            self.assertEqual(result["confirmed_by_user_id"], self.user_id)
            self.assertEqual(result["medication_confirmed_at"], first_time)
        rows = select_medications(family_room_id=self.room_id, medication_date=None,
                                  limit=100, offset=0, current_user_id=self.user_id)["results"]
        record = next(row for row in rows if row["medication_log_seq"] == self.seq)
        self.assertEqual(record["confirmed_by_name"], self.name)
        self.assertEqual(record["medication_confirmed_at"], first_time)


if __name__ == "__main__":
    unittest.main()
