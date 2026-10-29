"""월별 일정 조회와 등록 입력 검증을 실제 DB 없이 확인한다."""
import unittest
from datetime import date
from unittest.mock import MagicMock, patch

from fastapi import FastAPI
from fastapi.testclient import TestClient
from python.features.schedules.router import router, get_current_user_id


class ScheduleQueryTests(unittest.TestCase):
    def setUp(self):
        app = FastAPI()
        app.include_router(router)
        app.dependency_overrides[get_current_user_id] = lambda: 'family-user'
        self.client = TestClient(app)
        self.addCleanup(self.client.close)
        self.conn = MagicMock()
        self.cursor = self.conn.cursor.return_value.__enter__.return_value
        self.cursor.fetchone.return_value = {'participate_seq': 1}
        self.cursor.fetchall.return_value = [{
            'schedule_seq': 1, 'schedule_date': date(2026, 10, 25),
            'start_time': '09:00:00', 'end_time': '10:00:00',
        }]
        self.connect = self.enterContext(patch('python.features.schedules.router.connect', return_value=self.conn))

    def get(self, **changes):
        return self.client.get('/schedules', params={
            'family_room_id': 'room-a', 'year': 2026, 'month': 10, **changes,
        })

    def test_current_family_gets_month_and_serialized_dates(self):
        response = self.get()
        self.assertEqual(response.status_code, 200)
        self.assertEqual(response.json()['results'][0]['schedule_date'], '2026-10-25')
        membership_sql, membership_values = self.cursor.execute.call_args_list[0].args
        self.assertEqual(membership_values, ('room-a', 'family-user'))
        for clause in ('p.left_at IS NULL', 'f.family_room_deleted_at IS NULL', 'u.withdrawn_at IS NULL'):
            self.assertIn(clause, membership_sql)
        self.assertNotIn('is_representative', membership_sql)
        sql, values = self.cursor.execute.call_args_list[1].args
        self.assertEqual(values, ('room-a', date(2026, 10, 1), date(2026, 11, 1)))
        self.assertIn('s.deleted_at IS NULL', sql)
        self.assertIn('ORDER BY s.schedule_date, s.start_time, s.schedule_seq', sql)
        self.conn.close.assert_called_once()

    def test_december_wraps_to_next_year(self):
        self.assertEqual(self.get(year=2100, month=12).status_code, 200)
        values = self.cursor.execute.call_args_list[1].args[1]
        self.assertEqual(values[-1], date(2101, 1, 1))

    def test_nonmember_cannot_read(self):
        self.cursor.fetchone.return_value = None
        self.assertEqual(self.get().status_code, 403)
        self.assertEqual(self.cursor.execute.call_count, 1)
        self.conn.close.assert_called_once()

    def test_invalid_query_never_connects(self):
        for changes in ({'month': 0}, {'month': 13}, {'year': 2101}, {'family_room_id': ''}):
            self.assertEqual(self.get(**changes).status_code, 422)
        self.connect.assert_not_called()

    def test_database_failure_hides_details_and_closes(self):
        from pymysql import OperationalError
        self.cursor.execute.side_effect = OperationalError(2006, 'private')
        response = self.get()
        self.assertEqual(response.status_code, 503)
        self.assertNotIn('private', response.text)
        self.conn.close.assert_called_once()

    def test_missing_token_cannot_read(self):
        app = FastAPI()
        app.include_router(router)
        with TestClient(app) as client:
            self.assertEqual(client.get('/schedules', params={
                'family_room_id': 'room-a', 'year': 2026, 'month': 10,
            }).status_code, 401)
        self.connect.assert_not_called()

    def test_registration_rejects_equal_reversed_and_timezone_times(self):
        for start, end in [('09:00', '09:00'), ('10:00', '09:00'), ('09:00+09:00', '10:00')]:
            response = self.client.post('/schedules', json={
                'family_room_id': 'room-a', 'schedule_date': '2026-10-25',
                'start_time': start, 'end_time': end,
            })
            self.assertEqual(response.status_code, 422)
        self.connect.assert_not_called()


if __name__ == '__main__':
    unittest.main()
