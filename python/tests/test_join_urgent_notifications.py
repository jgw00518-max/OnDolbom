"""가입·긴급 일정 경계와 기존 알림의 푸시 연결을 외부 호출 없이 검사한다."""
import unittest
from datetime import datetime, timedelta
from unittest.mock import MagicMock, patch
from python.features.schedules import reminders, urgent_schedule
from python.features.notifications import store, schedule_notifications
from python.features.invites import router as invites
from python.features.notifications import space_events


class JoinUrgentNotificationTests(unittest.TestCase):
    def test_time_windows_never_overlap(self):
        start = datetime(2026, 11, 5, 12)
        for hours, reminder, urgent in [(73, False, False), (72, True, False),
                (24 + 1/3600, True, False), (24, False, True),
                (23, False, True), (1/3600, False, True), (0, False, False), (-1, False, False)]:
            with self.subTest(hours=hours):
                row = dict(schedule_date=start.date(), start_time='12:00:00',
                    server_now=start-timedelta(hours=hours), accepted_by=None,
                    deleted_at=None, schedule_state='미완료')
                self.assertEqual(reminders.is_due(row), reminder)
                self.assertEqual(urgent_schedule.is_urgent(row), urgent)
                self.assertFalse(reminders.is_due(row) and urgent_schedule.is_urgent(row))

    def test_within_72_hours_skips_regular_registration(self):
        conn = MagicMock()
        conn.cursor.return_value.__enter__.return_value.fetchone.return_value = {'within_reminder_window': 1}
        with patch.object(store, 'prepare') as prepare:
            self.assertFalse(schedule_notifications.prepare_schedule_notifications(conn, 1))
        prepare.assert_not_called()

    def test_join_retry_preserves_single_event_identifier(self):
        conn = MagicMock()
        conn.cursor.return_value.__enter__.return_value.fetchall.return_value = [{'user_id': 'new'}, {'user_id': 'guardian'}]
        from google.api_core.exceptions import AlreadyExists
        with patch.object(store, 'collection') as collection:
            identifier = space_events.prepare(conn, 'room', 'new', 'member_joined', 'invite')
            collection.return_value.document.return_value.create.side_effect = AlreadyExists('exists')
            with patch.object(store, 'get_event', return_value=dict(family_room_id='room', actor_id='new', source_id='invite', notification_type='member_joined')):
                self.assertEqual(space_events.prepare(conn, 'room', 'new', 'member_joined', 'invite'), identifier)
            self.assertEqual(collection.return_value.document.return_value.create.call_args.args[0]['recipient_ids'], ['guardian'])

    def test_supported_push_types(self):
        for kind in ['member_joined', 'family_room_deleted', 'schedule_urgent', 'schedule_reconfirm_urgent']:
            self.assertTrue(store.supports_push({'notification_type': kind}))

    def test_join_prepares_once_and_publishes_after_commit(self):
        conn = MagicMock()
        cursor = conn.cursor.return_value.__enter__.return_value
        cursor.fetchone.side_effect = [{'family_room_id': 'room'}, {'family_room_id': 'room'},
                                      {'invite_status': '대기', 'accepter_id': None}, None]
        def execute(sql, params):
            # 만료 판정 UPDATE는 0건, 실제 수락 UPDATE는 1건이다.
            cursor.rowcount = 0 if '<= CURRENT_TIMESTAMP' in sql else 1
        cursor.execute.side_effect = execute
        order = []
        conn.commit.side_effect = lambda: order.append('commit')
        with patch.object(invites, 'connect', return_value=conn), patch.object(invites, 'initialize_chat_read'), \
             patch.object(space_events, 'prepare', side_effect=lambda *a: order.append('prepare') or 'joined') as prepare, \
             patch.object(space_events, 'publish_safely', side_effect=lambda *a: order.append('publish')):
            result = invites.accept_invite('invite', {'user_id': 'new', 'user_email': 'new@example.com'})
        self.assertEqual(result['invite_status'], '수락')
        self.assertEqual(order, ['prepare', 'commit', 'publish'])
        prepare.assert_called_once_with(conn, 'room', 'new', 'member_joined', 'invite')

    def test_already_processed_invite_does_not_prepare_again(self):
        from fastapi import HTTPException
        conn = MagicMock()
        cursor = conn.cursor.return_value.__enter__.return_value
        cursor.fetchone.side_effect = [{'family_room_id': 'room'}, {'family_room_id': 'room'},
                                      {'invite_status': '수락', 'accepter_id': 'new'}]
        cursor.rowcount = 0
        with patch.object(invites, 'connect', return_value=conn), patch.object(space_events, 'prepare') as prepare:
            with self.assertRaises(HTTPException):
                invites.accept_invite('invite', {'user_id': 'new', 'user_email': 'new@example.com'})
        prepare.assert_not_called()


if __name__ == '__main__':
    unittest.main()
