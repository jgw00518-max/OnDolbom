import unittest
from unittest.mock import MagicMock, patch
from python.features.schedules.reminder_cache import CompletedReminders
from python.features.schedules import reminders, reminder_worker
from python.tests.features.test_schedule_reminders import schedule


class ReadSavingsTests(unittest.TestCase):
    def test_idle_backoff_and_busy_reset(self):
        interval = 5
        for expected in (10, 15, 15):
            interval = reminder_worker.next_push_interval(interval, 0)
            self.assertEqual(interval, expected)
        self.assertEqual(reminder_worker.next_push_interval(interval, 1), 5)

    def test_completed_cache_expiry_capacity_and_version(self):
        now = [0]
        cache = CompletedReminders(capacity=2, ttl=10, clock=lambda: now[0])
        cache.remember('schedule_v1')
        self.assertTrue(cache.contains('schedule_v1'))
        self.assertFalse(cache.contains('schedule_v2'))
        cache.remember('b')
        cache.remember('c')
        self.assertFalse(cache.contains('schedule_v1'))
        now[0] = 10
        self.assertFalse(cache.contains('c'))

    def test_completed_versions_skip_firestore_but_new_versions_recheck(self):
        connection = MagicMock()
        cursor = connection.cursor.return_value.__enter__.return_value
        cursor.fetchone.return_value = {'family_room_id': 'room'}
        cursor.fetchall.return_value = [{'user_id': 'family'}]
        publisher = MagicMock(return_value=False)  # 이미 발행된 기록을 확인한 경우도 기억한다.
        with patch.object(reminders, 'completed_reminders', CompletedReminders()), \
             patch.object(reminders, 'connect', return_value=connection), \
             patch.object(reminders, 'load_state', side_effect=[(schedule(), 'v1'), (schedule(), 'v1'), (schedule(), 'v2')]), \
             patch.object(reminders, 'collection') as collection, \
             patch.object(reminders.firestore, 'transactional', return_value=publisher):
            self.assertFalse(reminders.process_reminder(7))
            self.assertFalse(reminders.process_reminder(7))
            self.assertEqual(collection.call_count, 1)
            self.assertFalse(reminders.process_reminder(7))
            self.assertEqual(collection.call_count, 2)

    def test_failed_publication_is_not_cached(self):
        connection = MagicMock()
        cursor = connection.cursor.return_value.__enter__.return_value
        cursor.fetchone.return_value = {'family_room_id': 'room'}
        cursor.fetchall.return_value = [{'user_id': 'family'}]
        publisher = MagicMock(side_effect=[ValueError('offline'), True])
        with patch.object(reminders, 'completed_reminders', CompletedReminders()), \
             patch.object(reminders, 'connect', return_value=connection), \
             patch.object(reminders, 'load_state', return_value=(schedule(), 'v1')), \
             patch.object(reminders, 'collection') as collection, \
             patch.object(reminders.firestore, 'transactional', return_value=publisher):
            with self.assertRaises(ValueError):
                reminders.process_reminder(7)
            self.assertTrue(reminders.process_reminder(7))
            self.assertEqual(collection.call_count, 2)
