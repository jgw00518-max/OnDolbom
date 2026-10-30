import unittest
from datetime import date
from unittest.mock import MagicMock, patch
import pymysql
from fastapi.testclient import TestClient
from python.main import app
from python.features.medications.router import get_current_user_id


class MedicationPeriodTests(unittest.TestCase):
    def setUp(self):
        app.dependency_overrides[get_current_user_id] = lambda: 'guardian'
        self.addCleanup(app.dependency_overrides.pop, get_current_user_id)
        self.client = TestClient(app)
        self.addCleanup(self.client.close)
        self.db = MagicMock()
        self.cursor = self.db.cursor.return_value.__enter__.return_value
        self.cursor.fetchone.return_value = {'participate_seq': 1}
        self.cursor.lastrowid = 1
        self.payload = dict(family_room_id='room', medication_info='약',
            medication_date='2026-12-31', medication_time='아침', dosage_unit='정', dosage='1', duration_days=3)
        self.patch = patch('python.features.medications.router.connect', return_value=self.db)
        self.patch.start()
        self.addCleanup(self.patch.stop)

    def test_period_is_inclusive_atomic_and_has_one_unique_series(self):
        response = self.client.post('/medications/insert', json=self.payload)
        self.assertEqual(response.status_code, 201)
        rows = self.cursor.executemany.call_args.args[1]
        self.assertEqual([r[3] for r in rows], [date(2026, 12, 31), date(2027, 1, 1), date(2027, 1, 2)])
        self.assertEqual(len({r[-1] for r in rows}), 1)
        self.assertEqual(len(rows[0][-1]), 32)
        self.db.commit.assert_called_once()

    def test_presets_and_direct_input_boundaries(self):
        for days in [1, 2, 3, 5, 7, 30, 90, 365]:
            self.assertEqual(self.client.post('/medications/insert', json=dict(self.payload, duration_days=days)).status_code, 201)
        for days in [0, -1, 366, 1.5, True, '3']:
            self.assertEqual(self.client.post('/medications/insert', json=dict(self.payload, duration_days=days)).status_code, 422)
        self.assertEqual(self.client.post('/medications/insert', json=dict(self.payload, medication_date='9999-12-31')).status_code, 422)

    def test_partial_insert_failure_rolls_back_whole_period(self):
        self.cursor.executemany.side_effect = pymysql.OperationalError('failed')
        self.assertEqual(self.client.post('/medications/insert', json=self.payload).status_code, 500)
        self.db.commit.assert_not_called()
        self.db.rollback.assert_called_once()

    def test_delete_period_includes_today_and_completed_records_but_not_past(self):
        self.cursor.fetchone.side_effect = [{'participate_seq': 1}, {'medication_series_id': 'series'}]
        self.cursor.rowcount = 3
        response = self.client.request('DELETE', '/medications/delete/7', json={'family_room_id': 'room'})
        self.assertEqual(response.json(), {'result': 'OK', 'deleted_count': 3})
        sql, params = self.cursor.execute.call_args.args
        self.assertIn('medication_date>=CURRENT_DATE', sql)
        self.assertIn('record_deleted_at IS NULL', sql)
        self.assertNotIn('medication_confirmed_at IS NULL', sql)
        self.assertIn('medication_series_id=%s', sql)
        self.assertEqual(params, ('room', 'series'))

    def test_legacy_record_is_not_grouped_by_name(self):
        self.cursor.fetchone.side_effect = [{'participate_seq': 1}, {'medication_series_id': None}]
        self.cursor.rowcount = 0
        response = self.client.request('DELETE', '/medications/delete/7', json={'family_room_id': 'room'})
        self.assertEqual(response.status_code, 200)
        self.assertEqual(self.cursor.execute.call_args.args[1], ('room', 7))
        self.assertIn('medication_log_seq=%s', self.cursor.execute.call_args.args[0])

    def test_only_current_guardian_can_delete(self):
        self.cursor.fetchone.return_value = None
        response = self.client.request('DELETE', '/medications/delete/7', json={'family_room_id': 'room'})
        self.assertEqual(response.status_code, 403)
        self.db.commit.assert_not_called()
        self.cursor.executemany.assert_not_called()
