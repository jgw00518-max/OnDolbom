"""참여 철회의 권한·최신 요청·트랜잭션·수신자를 검증한다."""
import unittest
from datetime import datetime
from unittest.mock import MagicMock, patch
from fastapi import HTTPException
from python.features.schedules import withdraw_schedule as service
from python.features.schedules import router


class WithdrawalTests(unittest.TestCase):
    def setUp(self):
        self.conn = MagicMock()
        self.cursor = self.conn.cursor.return_value.__enter__.return_value
        self.cursor.rowcount = 1
        self.when = datetime(2026, 10, 29, 12)
        self.schedule = dict(schedule_seq=7, family_room_id='room', accepted_by='member',
            accepted_at=self.when, history_seq=12, deleted_at=None,
            schedule_state='미완료', created_at=self.when,
            schedule_date='2026-11-02', start_time='15:00:00', end_time='16:00:00',
            schedule_name='검수', schedule_memo='보존할 메모')
        self.cursor.fetchone.side_effect = [dict(family_room_id='room'),
            dict(family_room_id='room'), dict(user_id='member'),
            dict(update_accepted_by='member', update_accepted_at=self.when)]

    def withdraw(self, **expected):
        with patch.object(service, 'get_schedule_for_delete', return_value=self.schedule), \
             patch.object(router, 'insert_schedule_history', return_value=13) as history, \
             patch.object(service, 'prepare_withdrawal_notifications', return_value=['notice']) as notice:
            result = service.withdraw_schedule(self.conn, 7, 'member',
                expected.get('history', 12), expected.get('accepted_at', self.when))
        return result, history, notice

    def test_own_assignment_released_latest_content_preserved(self):
        result, history, notice = self.withdraw()
        self.assertEqual(result, (13, ['notice']))
        self.assertEqual(history.call_args.args[-1]['schedule_memo'], '보존할 메모')
        sql = ' '.join(str(call.args[0]) for call in self.cursor.execute.call_args_list)
        self.assertIn('accepted_by=NULL, accepted_at=NULL', sql)
        self.assertNotIn('DELETE', sql)
        self.conn.commit.assert_not_called()

    def test_wrong_assignee_or_already_released_blocked(self):
        for assignee in ('other', None):
            self.schedule['accepted_by'] = assignee
            self.setUpCursor()
            with self.assertRaises(HTTPException) as error:
                self.withdraw()
            self.assertEqual(error.exception.status_code, 409)

    def setUpCursor(self):
        self.cursor.fetchone.side_effect = [dict(family_room_id='room'),
            dict(family_room_id='room'), dict(user_id='member'),
            dict(update_accepted_by='member', update_accepted_at=self.when)]

    def test_stale_history_and_assignment_timestamp_blocked(self):
        for expected in (dict(history=11), dict(accepted_at=datetime(2026, 10, 28))):
            self.setUpCursor()
            with self.assertRaises(HTTPException) as error:
                self.withdraw(**expected)
            self.assertEqual(error.exception.status_code, 409)

    def test_pending_uses_existing_decline_flow(self):
        self.cursor.fetchone.side_effect = [dict(family_room_id='room'),
            dict(family_room_id='room'), dict(user_id='member'),
            dict(update_accepted_by='member', update_accepted_at=None)]
        with self.assertRaises(HTTPException) as error:
            self.withdraw()
        self.assertEqual(error.exception.status_code, 409)

    def test_nonmember_blocked(self):
        self.cursor.fetchone.side_effect = [dict(family_room_id='room'), dict(family_room_id='room'), None]
        with self.assertRaises(HTTPException) as error:
            self.withdraw()
        self.assertEqual(error.exception.status_code, 403)

    def test_deleted_and_completed_blocked(self):
        for key, value, code in (('deleted_at', self.when, 404), ('schedule_state', '완료', 409)):
            with self.subTest(key=key):
                self.setUpCursor()
                original = self.schedule[key]
                self.schedule[key] = value
                with self.assertRaises(HTTPException) as error:
                    self.withdraw()
                self.assertEqual(error.exception.status_code, code)
                self.schedule[key] = original

    def test_notice_preparation_failure_rolls_back(self):
        payload = router.ScheduleWithdrawal(expected_history_seq=12, expected_accepted_at=self.when)
        with patch.object(router, 'connect', return_value=self.conn), \
             patch.object(service, 'withdraw_schedule', side_effect=ValueError('notice failed')), \
             self.assertLogs(router.logger, level='ERROR'):
            with self.assertRaises(HTTPException):
                router.withdraw_schedule_participation(payload, 7, 'member')
        self.conn.rollback.assert_called_once()
        self.conn.commit.assert_not_called()

    def test_publication_failure_preserves_committed_withdrawal(self):
        payload = router.ScheduleWithdrawal(expected_history_seq=12, expected_accepted_at=self.when)
        with patch.object(router, 'connect', return_value=self.conn), \
             patch.object(service, 'withdraw_schedule', return_value=(13, ['guardian', 'recruitment'])), \
             patch.object(service, 'publish_withdrawal_notification', side_effect=ValueError('offline')), \
             self.assertLogs(router.logger, level='ERROR'):
            result = router.withdraw_schedule_participation(payload, 7, 'member')
        self.assertFalse(result['notification_published'])
        self.conn.commit.assert_called_once()
        self.conn.rollback.assert_not_called()

    def test_guardian_notice_and_all_family_recruitment_separate(self):
        self.cursor.fetchall.return_value = [dict(user_id='guardian', is_representative=1, name='보호자'),
            dict(user_id='member', is_representative=0, name='담당'),
            dict(user_id='other', is_representative=0, name='가족')]
        self.cursor.fetchone.side_effect = [dict(updated_at=self.when)]
        with patch.object(service, 'prepare_change', side_effect=['guardian-event', 'recruit-event']) as prepare:
            service.prepare_withdrawal_notifications(self.conn, self.schedule, 13, 'member')
        first, second = [call.args[0] for call in prepare.call_args_list]
        self.assertEqual(first['recipient_ids'], ['guardian'])
        self.assertEqual(first['notification_type'], 'schedule_withdrawn')
        self.assertEqual(set(second['recipient_ids']), {'guardian', 'other'})
        self.assertEqual(second['reason'], 'participation_withdrawal')

    def test_missing_auth_is_rejected(self):
        from fastapi import FastAPI
        from fastapi.testclient import TestClient
        app = FastAPI()
        app.include_router(router.router)
        with TestClient(app) as client:
            response = client.post('/schedules/7/withdraw', json={
                'expected_history_seq': 12, 'expected_accepted_at': self.when.isoformat()})
        self.assertEqual(response.status_code, 401)
