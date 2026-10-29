"""수신자 정책 회귀 검사."""
import unittest
from unittest.mock import Mock
from python.features.notifications.store import _prepare, exclude_actor
from python.features.schedules.change_notifications import _prepare_change


class ActorRecipientTests(unittest.TestCase):
    def test_manual_events_exclude_only_actual_actor(self):
        for kind in ('schedule_created', 'schedule_changed', 'schedule_deleted',
                     'schedule_accepted', 'schedule_reconfirmed', 'schedule_reconfirm',
                     'schedule_recruitment'):
            with self.subTest(kind=kind):
                payload = dict(notification_type=kind, actor_id='actor',
                               recipient_ids=['actor', 'guardian', 'family'])
                self.assertEqual(exclude_actor(payload)['recipient_ids'], ['guardian', 'family'])
                self.assertEqual(payload['recipient_ids'], ['actor', 'guardian', 'family'])

    def test_automatic_reminder_keeps_creator(self):
        payload = dict(notification_type='schedule_reminder', actor_id='actor',
                       recipient_ids=['actor', 'family'])
        self.assertEqual(exclude_actor(payload)['recipient_ids'], ['actor', 'family'])

    def test_both_stores_persist_filtered_recipients_without_blocking_solo_space(self):
        for prepare in (_prepare, _prepare_change):
            transaction, ref = Mock(), Mock()
            ref.get.return_value.exists = False
            prepare(transaction, ref, dict(actor_id='actor', recipient_ids=['actor']))
            self.assertEqual(transaction.create.call_args.args[1]['recipient_ids'], [])

    def test_system_events_keep_existing_recipients(self):
        self.assertEqual(exclude_actor(dict(recipient_ids=['a', 'b']))['recipient_ids'], ['a', 'b'])
