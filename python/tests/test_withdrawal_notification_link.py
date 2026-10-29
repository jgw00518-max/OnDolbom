"""철회 전용 알림과 재모집을 공통 알림함·푸시에 연결한다."""
import unittest
from unittest.mock import MagicMock, patch
from python.features.notifications import store, push
from python.features.schedules import withdraw_schedule as withdrawal
from python.features.schedules import notification_router as api


class WithdrawalLinkTests(unittest.TestCase):
    def test_withdrawal_is_in_v2_inbox_and_push_types(self):
        event = {'notification_type': 'schedule_withdrawn'}
        with patch.object(api, '_visible', return_value={'read_at': None}) as visible:
            self.assertIsNotNone(api.visible_v2(None, 'guardian', event))
            visible.assert_called_once_with(None, 'guardian', event)
        self.assertTrue(store.supports_push(event))
        # 자동 만료도 후속 연결되어 철회와 함께 푸시 대상에 포함된다.
        self.assertTrue(store.supports_push({'notification_type': 'schedule_reconfirm_expired'}))

    def test_withdrawal_recruitment_does_not_become_declined_for_guardian(self):
        for guardian in [0, 1]:
            conn = MagicMock()
            cursor = conn.cursor.return_value.__enter__.return_value
            cursor.fetchone.side_effect = [{'created_at': 'stamp'}, {'is_representative': guardian}]
            event = dict(status='published', recipient_ids=['user'], schedule_seq=7,
                         family_room_id='room', schedule_created_at='stamp', created_at='now',
                         notification_type='schedule_recruitment', reason='participation_withdrawal')
            with patch.object(store, 'inbox_state', return_value={}):
                row = api._visible(conn, 'user', event)
            self.assertEqual(row['notification_type'], 'schedule_recruitment')

    def test_reconfirmation_decline_keeps_existing_guardian_copy(self):
        conn = MagicMock()
        cursor = conn.cursor.return_value.__enter__.return_value
        cursor.fetchone.side_effect = [{'created_at': 'stamp'}, {'is_representative': 1}]
        event = dict(status='published', recipient_ids=['user'], schedule_seq=7,
                     family_room_id='room', schedule_created_at='stamp', created_at='now',
                     notification_type='schedule_recruitment')
        with patch.object(store, 'inbox_state', return_value={}):
            self.assertEqual(api._visible(conn, 'user', event)['notification_type'], 'schedule_declined')

    def test_publish_withdrawal_enqueues_push_once(self):
        tx, ref = MagicMock(), MagicMock()
        ref.get.return_value.exists = True
        ref.get.return_value.to_dict.return_value = dict(status='pending', schedule_created_at='stamp',
                                                         notification_type='schedule_withdrawn')
        self.assertTrue(store._publish(tx, ref, 'stamp'))
        self.assertTrue(tx.update.call_args.args[1]['push_pending'])
        tx.reset_mock()
        ref.get.return_value.to_dict.return_value = dict(status='published', schedule_created_at='stamp',
                                                         notification_type='schedule_withdrawn')
        self.assertTrue(store._publish(tx, ref, 'stamp'))
        tx.update.assert_not_called()

    def test_withdrawal_push_has_specific_message_and_existing_notification_route(self):
        with patch.object(push, 'get_firebase_app'), patch.object(push.messaging, 'send') as send:
            push.send_message('device-token', 'uid', 'schedule_withdrawn_7_13', notification_type='schedule_withdrawn')
        message = send.call_args.args[0]
        self.assertIn('참여를 취소', message.notification.body)
        self.assertEqual(message.data['notification_id'], 'schedule_withdrawn_7_13')
        self.assertEqual(message.data['type'], 'schedule_withdrawn')
        self.assertEqual(message.data['user_uid'], 'uid')

    def test_preparation_excludes_actor_and_does_not_create_empty_events(self):
        for actor, members, expected in [
            ('member', [dict(user_id='guardian', is_representative=1, name='주보호자'),
                        dict(user_id='member', is_representative=0, name='담당')],
             [('schedule_withdrawn', {'guardian'}), ('schedule_recruitment', {'guardian'})]),
            ('guardian', [dict(user_id='guardian', is_representative=1, name='주보호자'),
                          dict(user_id='member', is_representative=0, name='가족')],
             [('schedule_recruitment', {'member'})]),
            ('guardian', [dict(user_id='guardian', is_representative=1, name='주보호자')], []),
        ]:
            conn = MagicMock()
            cursor = conn.cursor.return_value.__enter__.return_value
            cursor.fetchall.return_value = members
            cursor.fetchone.return_value = {'updated_at': 'changed'}
            with patch.object(withdrawal, 'prepare_change', return_value='event') as prepare:
                withdrawal.prepare_withdrawal_notifications(conn, {'schedule_seq': 7, 'family_room_id': 'room', 'created_at': 'created'}, 13, actor)
            actual = [(call.args[0]['notification_type'], set(call.args[0]['recipient_ids'])) for call in prepare.call_args_list]
            self.assertEqual(actual, expected)
            for call in prepare.call_args_list:
                self.assertEqual(call.args[0]['actor_id'], actor)
                self.assertNotIn(actor, call.args[0]['recipient_ids'])

    def test_legacy_event_does_not_send_actor_his_own_withdrawal(self):
        event = dict(status='published', recipient_ids=['actor'], reason='participation_withdrawal',
                     former_assignee_id='actor', notification_type='schedule_recruitment')
        conn = MagicMock()
        self.assertIsNone(api._visible(conn, 'actor', event))
        conn.cursor.assert_not_called()


if __name__ == '__main__': unittest.main()
