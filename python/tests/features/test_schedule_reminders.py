import unittest
from datetime import date, datetime, timedelta
from unittest.mock import MagicMock, patch
from python.features.schedules import reminders as api
from python.features.schedules import notification_router as inbox
from python.features.schedules import router as routes


def schedule(**changes):
    return dict(dict(schedule_seq=7, family_room_id='room', created_at=datetime(2026, 10, 1),
                     schedule_date=date(2026, 10, 31), start_time='09:00:00',
                     server_now=datetime(2026, 10, 28, 9), accepted_by=None,
                     schedule_state='미완료', deleted_at=None), **changes)


class ScheduleReminderTests(unittest.TestCase):
    def setUp(self):
        replacement = patch.object(api, 'completed_reminders', api.completed_reminders.__class__())
        replacement.start()
        self.addCleanup(replacement.stop)

    def test_72_hour_boundary_and_started_completed_assigned_deleted_exclusions(self):
        row = schedule()
        self.assertTrue(api.is_due(row))
        self.assertFalse(api.is_due(schedule(server_now=row['server_now'] - timedelta(seconds=1))))
        self.assertTrue(api.is_due(schedule(server_now=datetime(2026, 10, 31, 8, 59, 59))))
        self.assertFalse(api.is_due(schedule(server_now=datetime(2026, 10, 31, 9))))
        self.assertFalse(api.is_due(schedule(server_now=datetime(2026, 10, 31, 10))))
        for changes in [dict(accepted_by='family'), dict(schedule_state='완료'), dict(deleted_at='deleted')]:
            self.assertFalse(api.is_due(schedule(**changes)))

    def test_non_start_edits_do_not_duplicate_and_returning_to_old_time_is_new_revision(self):
        row = schedule()
        _, original = api.reminder_state(row, [])
        same = dict(history_seq=1, schedule_date=row['schedule_date'], start_time='09:00:00')
        _, unchanged = api.reminder_state(row, [same])
        self.assertEqual(original, unchanged)
        moved = dict(same, history_seq=2, start_time='10:00:00')
        _, changed = api.reminder_state(row, [same, moved])
        self.assertNotEqual(original, changed)
        _, still_changed = api.reminder_state(row, [same, moved, dict(moved, history_seq=3)])
        self.assertEqual(changed, still_changed)
        _, restored = api.reminder_state(row, [same, moved, dict(same, history_seq=4)])
        self.assertNotEqual(original, restored)

    def test_publication_is_atomic_and_never_resets_read_receipts(self):
        ref, transaction = MagicMock(), MagicMock()
        ref.get.return_value.exists = False
        self.assertTrue(api._publish_once(transaction, ref, {'notification_id': 'stable'}))
        transaction.set.assert_called_once()
        self.assertTrue(transaction.set.call_args.args[1]['push_pending'])
        ref.get.return_value.exists = True
        ref.get.return_value.to_dict.return_value = {'status': 'published'}
        self.assertFalse(api._publish_once(transaction, ref, {'notification_id': 'stable'}))
        transaction.set.assert_called_once()

    def test_dispatch_rechecks_under_locks_and_resolves_current_recipients(self):
        connection = MagicMock()
        cursor = connection.cursor.return_value.__enter__.return_value
        cursor.fetchone.side_effect = [dict(family_room_id='room'), dict(family_room_id='room'), schedule()]
        cursor.fetchall.side_effect = [[], [{'user_id': 'guardian'}, {'user_id': 'family'}]]
        publish = MagicMock(return_value=True)
        with patch.object(api, 'connect', return_value=connection), patch.object(api, 'collection'), \
             patch.object(api.firestore, 'transactional', return_value=publish):
            self.assertTrue(api.process_reminder(7))
        payload = publish.call_args.args[2]
        self.assertEqual(payload['recipient_ids'], ['family', 'guardian'])
        self.assertEqual(payload['notification_type'], 'schedule_reminder')
        self.assertTrue(payload['notification_id'].startswith('schedule_reminder_7_'))
        sql = [call.args[0] for call in cursor.execute.call_args_list]
        self.assertIn('family_room_deleted_at IS NULL FOR UPDATE', sql[1])
        self.assertIn('FOR UPDATE', sql[2])
        self.assertIn('FOR UPDATE', sql[3])
        self.assertIn('p.left_at IS NULL', sql[-1])
        self.assertIn('u.withdrawn_at IS NULL', sql[-1])
        self.assertFalse(any(text.lstrip().startswith(('UPDATE ', 'INSERT ', 'DELETE ')) for text in sql))
        connection.rollback.assert_called_once()
        connection.close.assert_called_once()

    def test_assigned_or_moved_outside_window_never_writes_firestore(self):
        for row in [schedule(accepted_by='family'), schedule(server_now=datetime(2026, 10, 27)),
                    schedule(deleted_at='deleted'), schedule(schedule_state='완료')]:
            connection = MagicMock()
            cursor = connection.cursor.return_value.__enter__.return_value
            cursor.fetchone.side_effect = [dict(family_room_id='room'), dict(family_room_id='room'), row]
            cursor.fetchall.return_value = []
            with patch.object(api, 'connect', return_value=connection), patch.object(api, 'collection') as collection:
                self.assertFalse(api.process_reminder(7))
                collection.assert_not_called()
            connection.close.assert_called_once()

    def test_deleted_space_never_writes_firestore(self):
        connection = MagicMock()
        connection.cursor.return_value.__enter__.return_value.fetchone.side_effect = [dict(family_room_id='room'), None]
        with patch.object(api, 'connect', return_value=connection), patch.object(api, 'collection') as collection:
            self.assertFalse(api.process_reminder(7))
            collection.assert_not_called()

    def test_stale_reminders_are_hidden_from_list_and_badges(self):
        _, key = api.reminder_state(schedule(), [])
        event = dict(schedule_seq=7, family_room_id='room', schedule_created_at=str(schedule()['created_at']), reminder_key=key)
        with patch.object(api, 'load_state', return_value=(schedule(), key)):
            self.assertTrue(api.reminder_is_current(None, event))
        for state in [(schedule(accepted_by='family'), key), (schedule(), 'new-key'),
                      (schedule(deleted_at='deleted'), key)]:
            with patch.object(api, 'load_state', return_value=state):
                self.assertFalse(api.reminder_is_current(None, event))
        with patch.object(inbox, 'reminder_is_current', return_value=False):
            hidden = dict(event, status='published', recipient_ids=['family'], notification_type='schedule_reminder')
            self.assertIsNone(inbox.visible_v2(None, 'family', hidden))

    def test_worker_continues_after_failure_and_retries_on_next_scan(self):
        connection = MagicMock()
        connection.cursor.return_value.__enter__.return_value.fetchall.return_value = [{'schedule_seq': 7}, {'schedule_seq': 8}]
        with patch.object(api, 'connect', return_value=connection), \
             patch.object(api, 'process_reminder', side_effect=[ValueError('offline'), True, True, False]), \
             self.assertLogs(api.logger, level='ERROR'):
            self.assertEqual(api.check_reminders(), 1)
            self.assertEqual(api.check_reminders(), 1)

    def test_urgent_registration_publishes_only_reminder(self):
        connection = MagicMock()
        connection.cursor.return_value.__enter__.return_value.lastrowid = 7
        data = routes.ScheduleCreate(family_room_id='room', schedule_date='2026-10-31',
                                     start_time='11:00', end_time='12:00')
        with patch.object(routes, 'connect', return_value=connection), \
             patch.object(routes, 'check_representative'), patch.object(routes, 'check_schedule_overlap'), \
             patch.object(routes, 'prepare_schedule_notifications', return_value=False), \
             patch.object(routes, 'publish_schedule_notifications') as publish, \
             patch.object(routes, 'try_remind', return_value=True) as remind:
            result = routes.create_schedule(data, 'guardian')
        publish.assert_not_called()
        remind.assert_called_once_with(7)
        self.assertFalse(result['notification_published'])
        self.assertTrue(result['reminder_published'])
        connection.commit.assert_called_once()

    def test_registration_and_time_change_trigger_immediate_check_after_commit(self):
        for update in [False, True]:
            connection = MagicMock()
            cursor = connection.cursor.return_value.__enter__.return_value
            cursor.lastrowid = 7
            cursor.fetchone.side_effect = [dict(schedule(), schedule_name='old', end_time='10:00:00', schedule_memo=None), None]
            data = routes.ScheduleCreate(family_room_id='room', schedule_date='2026-10-31',
                                         start_time='11:00', end_time='12:00')
            def remind(identifier):
                connection.commit.assert_called_once()
                self.assertEqual(identifier, 7)
                return True
            with patch.object(routes, 'connect', return_value=connection), \
                 patch.object(routes, 'check_representative'), patch.object(routes, 'check_schedule_overlap'), \
                 patch.object(routes, 'prepare_schedule_notifications'), \
                 patch.object(routes, 'publish_schedule_notifications', return_value=True), \
                 patch.object(routes, 'get_pending_reconfirm_request', return_value=None), \
                 patch.object(routes, 'insert_schedule_history', return_value=12), \
                 patch.object(routes, 'try_remind', side_effect=remind):
                result = routes.update_schedule(data, 7, 'guardian') if update else routes.create_schedule(data, 'guardian')
            self.assertTrue(result['reminder_published'])


if __name__ == '__main__':
    unittest.main()
