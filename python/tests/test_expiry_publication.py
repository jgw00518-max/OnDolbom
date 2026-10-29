"""기한 있는 긴급 만료는 발행하고 기한 없는 요청·조기 처리는 막는다."""
import unittest
from datetime import datetime, timedelta
from unittest.mock import MagicMock, patch
from python.features.schedules import change_notifications as notices


class ExpiryPublicationTests(unittest.TestCase):
    def check_case(self, remaining, processed_after, expected, kind):
        requested = datetime(2026, 10, 29, 16, 43)
        starts = requested + timedelta(hours=remaining)
        from python.features.schedules.reconfirm_policy import get_reconfirm_deadline
        due = get_reconfirm_deadline(requested, starts.date(), starts.time())['response_due_at']
        processed = (due or requested) + timedelta(seconds=processed_after)
        saved = dict(family_room_id='room', created_at=requested,
                     updated_at=processed, former_assignee_id='member',
                     requested_at=requested, schedule_date=starts.date(),
                     start_time=starts.time())
        identifier = f'{kind}_40_114'
        event = dict(notification_id=identifier, notification_type=kind,
                     status='pending', schedule_seq=40, history_seq=114,
                     request_history_seq=113, family_room_id='room',
                     schedule_created_at=str(requested), history_updated_at=str(processed),
                     former_assignee_id='member', response_due_at=str(due),
                     processed_by='system', reason='response_timeout',
                     recipient_ids=['member' if kind.endswith('_expired') else 'guardian'])
        conn = MagicMock()
        conn.cursor.return_value.__enter__.return_value.fetchone.return_value = saved
        with patch.object(notices, 'connect', return_value=conn), \
             patch.object(notices, 'get_event', return_value=event), \
             patch.object(notices, 'publish', return_value=True) as publish:
            result = notices.publish_reconfirm_expiry_notification(identifier)
        self.assertEqual(result, expected)
        self.assertEqual(publish.call_count, int(expected))
        conn.close.assert_called_once()

    def test_urgent_with_deadline_publishes_both_notices_at_deadline(self):
        for kind in ('schedule_reconfirm_expired', 'schedule_reconfirm_unanswered'):
            with self.subTest(kind=kind):
                self.check_case(18, 0, True, kind)

    def test_urgent_without_deadline_never_publishes(self):
        self.check_case(12, 60, False, 'schedule_reconfirm_expired')

    def test_before_deadline_never_publishes(self):
        self.check_case(18, -1, False, 'schedule_reconfirm_expired')

    def test_general_request_still_publishes(self):
        self.check_case(48, 1, True, 'schedule_reconfirm_expired')
