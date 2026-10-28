import unittest
from unittest.mock import MagicMock, patch
from fastapi import HTTPException
from python.features.schedules import response_notifications as notices
from python.features.schedules import router as schedules
from python.features.schedules import notification_router as inbox


class ResponseNotificationsTests(unittest.TestCase):
    def test_only_current_guardians_receive_acceptance_and_reconfirmation(self):
        for history, kind in [(None, 'schedule_accepted'), (12, 'schedule_reconfirmed')]:
            connection = MagicMock()
            cursor = connection.cursor.return_value.__enter__.return_value
            cursor.fetchone.return_value = dict(family_room_id='room', created_at='created', accepted_at='accepted', name='Family')
            cursor.fetchall.return_value = [{'user_id': 'guardian'}]
            prepare = MagicMock()
            with patch.object(notices, 'collection'), patch.object(notices.firestore, 'transactional', return_value=prepare):
                identifier, fingerprint = notices.prepare_response_notification(connection, 7, 'family', history)
            payload = prepare.call_args.args[2]
            self.assertEqual(payload['recipient_ids'], ['guardian'])
            self.assertEqual(payload['notification_type'], kind)
            self.assertEqual(payload['actor_id'], 'family')
            self.assertTrue(identifier.startswith(kind + '_7_'))
            self.assertEqual(fingerprint, 'created')
            sql = cursor.execute.call_args.args[0]
            for condition in ['is_representative=1', 'left_at IS NULL', 'withdrawn_at IS NULL']:
                self.assertIn(condition, sql)
            connection.commit.assert_not_called()

    def test_acceptance_prepare_failure_rolls_back_but_publication_failure_keeps_commit(self):
        for prepare_error in [True, False]:
            connection = MagicMock()
            cursor = connection.cursor.return_value.__enter__.return_value
            cursor.fetchone.side_effect = [dict(family_room_id='room'), dict(family_room_id='room'),
                dict(family_room_id='room', schedule_state='미완료', accepted_by=None), dict(is_representative=0)]
            cursor.rowcount = 1
            with patch.object(schedules, 'connect', return_value=connection), \
                 patch.object(schedules, 'prepare_response_notification', side_effect=ValueError('failed') if prepare_error else None, return_value=('notice', 'created')), \
                 patch.object(schedules, 'publish_response_notification', side_effect=ValueError('failed')):
                if prepare_error:
                    with self.assertRaises(HTTPException) as caught:
                        schedules.accept_schedule(7, 'family')
                    self.assertEqual(caught.exception.status_code, 503)
                    connection.rollback.assert_called_once()
                    connection.commit.assert_not_called()
                else:
                    result = schedules.accept_schedule(7, 'family')
                    self.assertFalse(result['response_notification_published'])
                    connection.commit.assert_called_once()
                    connection.rollback.assert_not_called()

    def test_decline_copy_depends_on_current_role(self):
        for representative, expected in [(1, 'schedule_declined'), (0, 'schedule_recruitment')]:
            connection = MagicMock()
            cursor = connection.cursor.return_value.__enter__.return_value
            cursor.fetchone.side_effect = [dict(created_at='created'), dict(is_representative=representative)]
            event = dict(status='published', recipient_ids=['member'], notification_type='schedule_recruitment',
                schedule_seq=7, family_room_id='room', schedule_created_at='created', created_at='now', notification_id='schedule_recruitment_7_12')
            with patch.object(inbox.store, 'read_at', return_value=None):
                self.assertEqual(inbox._visible(connection, 'member', event)['notification_type'], expected)

    def test_reconfirmation_publishes_guardian_result_after_commit(self):
        connection = MagicMock()
        cursor = connection.cursor.return_value.__enter__.return_value
        cursor.fetchone.side_effect = [dict(family_room_id='room'), dict(family_room_id='room'),
            dict(accepted_by='family', schedule_state='미완료'), dict(participate_seq=1),
            dict(update_accepted_by='family', update_accepted_at=None)]
        pending = dict(request_history_seqs=[12], request_history_seq=12, requested_at='now',
                       current=dict(schedule_date='date', start_time='09:00'))
        def publish(prepared):
            connection.commit.assert_called_once()
            return True
        with patch.object(schedules, 'connect', return_value=connection), \
             patch.object(schedules, 'get_pending_reconfirm_request', return_value=pending), \
             patch.object(schedules, 'get_reconfirm_deadline', return_value={'is_urgent': True}), \
             patch.object(schedules, 'insert_schedule_history', return_value=13), \
             patch.object(schedules, 'prepare_response_notification', return_value=('event', 'created')) as prepare, \
             patch.object(schedules, 'publish_response_notification', side_effect=publish), \
             patch.object(schedules, 'prepare_recruitment_notification') as recruit:
            result = schedules.respond_schedule_change(schedules.ScheduleReconfirmAnswer(accepted=True), 7, 12, 'family')
        prepare.assert_called_once_with(connection, 7, 'family', 13)
        recruit.assert_not_called()
        self.assertTrue(result['response_notification_published'])


if __name__ == '__main__':
    unittest.main()
