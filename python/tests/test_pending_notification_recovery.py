"""외부 DB와 Firebase를 호출하지 않고 미발행 복구 경로를 검증한다."""
import unittest
from unittest.mock import MagicMock, patch
from python.features.schedules import reconfirm_expiry_worker as worker
from python.features.schedules import response_notifications as response


class PendingRecoveryTest(unittest.TestCase):
    def test_routes_missing_types_and_legacy_registration(self):
        events = [(None, '7'), ('schedule_created', '7'),
                  ('schedule_changed', 'schedule_changed_7_9'),
                  ('schedule_reconfirm', 'schedule_reconfirm_7_9'),
                  ('schedule_accepted', 'schedule_accepted_7_uuid'),
                  ('schedule_reconfirmed', 'schedule_reconfirmed_7_9')]
        snapshots = []
        for kind, identifier in events:
            snapshot = MagicMock(id=identifier)
            snapshot.to_dict.return_value = dict(notification_type=kind, schedule_seq=7, history_seq=9)
            snapshots.append(snapshot)
        with patch.object(worker, 'collection') as collection, \
             patch.object(worker, 'publish_schedule_notifications') as created, \
             patch.object(worker, 'publish_schedule_change_notification') as changed, \
             patch.object(worker, 'publish_reconfirm_notification') as reconfirm, \
             patch.object(worker, 'retry_response_notification') as result:
            collection.return_value.where.return_value.stream.return_value = snapshots
            worker.retry_pending_notifications()
            self.assertEqual(created.call_count, 2)
            changed.assert_called_once_with(7, 9)
            reconfirm.assert_called_once_with(7, 9)
            self.assertEqual(result.call_count, 2)

    def test_response_revalidates_before_publish(self):
        event = dict(notification_type='schedule_accepted', notification_id='schedule_accepted_7_uuid',
                     schedule_seq=7, history_seq=None, actor_id='actor', family_room_id='room',
                     schedule_created_at='created', history_updated_at='accepted', status='pending')
        conn = MagicMock()
        cursor = conn.cursor.return_value.__enter__.return_value
        cursor.fetchone.return_value = dict(family_room_id='room', created_at='created', accepted_at='accepted')
        with patch.object(response, 'get_event', return_value=event), \
             patch.object(response, 'connect', return_value=conn), \
             patch.object(response, 'publish', return_value=True) as publish:
            self.assertTrue(response.retry_response_notification(event['notification_id']))
            publish.assert_called_once_with(event['notification_id'], 'created')
            publish.reset_mock()
            cursor.fetchone.return_value['accepted_at'] = 'newer'
            self.assertFalse(response.retry_response_notification(event['notification_id']))
            publish.assert_not_called()
        self.assertEqual(conn.close.call_count, 2)

    def test_rolled_back_response_is_not_published(self):
        event = dict(notification_type='schedule_reconfirmed', notification_id='schedule_reconfirmed_7_9',
                     schedule_seq=7, history_seq=9, actor_id='actor', family_room_id='room',
                     schedule_created_at='created', history_updated_at='accepted', status='pending')
        conn = MagicMock()
        conn.cursor.return_value.__enter__.return_value.fetchone.return_value = None
        with patch.object(response, 'get_event', return_value=event), \
             patch.object(response, 'connect', return_value=conn), \
             patch.object(response, 'publish') as publish:
            self.assertFalse(response.retry_response_notification(event['notification_id']))
            publish.assert_not_called()
        conn.close.assert_called_once()
