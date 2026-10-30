"""자동 만료·미응답·재모집·긴급 미확인의 앱/배지/푸시 연결을 외부 호출 없이 검증한다."""
import unittest
from unittest.mock import MagicMock, patch
from python.features.schedules import notification_router as api
from python.features.notifications import store, push
from python.features.activity import router as activity

KINDS = ['schedule_reconfirm_expired', 'schedule_reconfirm_unanswered',
         'schedule_recruitment', 'schedule_reconfirm_unverified']


def event(kind, recipients):
    return dict(status='published', notification_type=kind, notification_id=kind + '_7_13',
                schedule_seq=7, history_seq=13, family_room_id='room', schedule_created_at='stamp',
                created_at='now', recipient_ids=recipients, request_history_seq=12,
                reason='urgent_response_unverified' if kind.endswith('unverified') else 'response_timeout')


class AutomaticNotificationLinkTests(unittest.TestCase):
    def setUp(self):
        self.conn = MagicMock()
        self.cursor = self.conn.cursor.return_value.__enter__.return_value
        self.cursor.fetchone.return_value = {'created_at': 'stamp'}

    def test_current_access_and_original_recipient_boundaries_are_kept(self):
        for kind, recipients in [(KINDS[0], ['former']), (KINDS[1], ['guardian']),
                                 (KINDS[2], ['former', 'guardian', 'other']), (KINDS[3], ['guardian'])]:
            with patch.object(store, 'inbox_state', return_value={}):
                for user in ['former', 'guardian', 'other', 'outsider']:
                    row = api.visible_v2(self.conn, user, event(kind, recipients))
                    self.assertEqual(row is not None, user in recipients)
                    if row is not None: self.assertEqual(row['notification_type'], kind)
        self.assertIn('p.left_at IS NULL', self.cursor.execute.call_args.args[0])

    def test_ended_space_or_reused_schedule_does_not_leak_notification(self):
        sample = event(KINDS[0], ['former'])
        for saved in [None, {'created_at': 'another-stamp'}]:
            self.cursor.fetchone.return_value = saved
            with patch.object(store, 'inbox_state') as receipts:
                self.assertIsNone(api.visible_v2(self.conn, 'former', sample))
                receipts.assert_not_called()

    def test_automatic_recruitment_is_not_a_decline_even_if_guardian_views_it(self):
        sample = event('schedule_recruitment', ['guardian'])
        # reason으로도 구분하므로 누락된 이전 요청 번호가 거절 문구로 바뀌지 않는다.
        sample.pop('request_history_seq')
        with patch.object(store, 'inbox_state', return_value={}):
            row = api.visible_v2(self.conn, 'guardian', sample)
        self.assertEqual(row['notification_type'], 'schedule_recruitment')
        self.assertEqual(self.cursor.execute.call_count, 1)

    def test_read_receipts_and_personal_deletion_are_preserved(self):
        sample = event(KINDS[1], ['guardian'])
        with patch.object(store, 'inbox_state', return_value={'read_at': 'first'}):
            self.assertEqual(api.visible_v2(self.conn, 'guardian', sample)['read_at'], 'first')
        with patch.object(store, 'inbox_state', return_value={'read_at': 'first', 'deleted_at': 'hidden'}):
            self.assertIsNone(api.visible_v2(self.conn, 'guardian', sample))

    def test_badge_uses_same_recipient_rules_as_inbox(self):
        rows = [event(KINDS[0], ['former']), event(KINDS[1], ['guardian']),
                event(KINDS[2], ['former', 'guardian', 'other']), event(KINDS[3], ['guardian'])]
        with patch.object(activity, 'list_notification_events', return_value=rows), \
             patch.object(store, 'inbox_state', return_value={}):
            for user, expected in [('former', 2), ('guardian', 3), ('other', 1), ('outsider', 0)]:
                self.assertEqual(activity.notification_count(self.conn, user), expected)

    def test_new_publish_queues_fcm_but_replaying_published_event_does_not(self):
        for kind in KINDS:
            sample = event(kind, ['user'])
            sample['status'] = 'pending'
            sample['actor_id'] = None
            self.assertEqual(store.exclude_actor(sample)['recipient_ids'], ['user'])
            self.assertTrue(store.supports_push(sample))
            tx, ref = MagicMock(), MagicMock()
            ref.get.return_value.exists = True
            ref.get.return_value.to_dict.return_value = sample
            self.assertTrue(store._publish(tx, ref, 'stamp'))
            self.assertTrue(tx.update.call_args.args[1]['push_pending'])
            tx.reset_mock(); sample['status'] = 'published'
            self.assertTrue(store._publish(tx, ref, 'stamp'))
            tx.update.assert_not_called()

    def test_specific_fcm_messages_use_current_inbox_routing(self):
        words = ['배정이 해제', '응답하지 않아', '다시 모집', '직접 확인']
        for kind, word in zip(KINDS, words):
            with patch.object(push, 'get_firebase_app'), patch.object(push.messaging, 'send') as send:
                push.send_message('device', 'uid', kind + '_7_13', notification_type=kind)
            message = send.call_args.args[0]
            self.assertIn(word, message.notification.body)
            self.assertEqual(message.data, {'notification_id': kind + '_7_13', 'type': kind, 'user_uid': 'uid'})
            self.assertNotIn('새 돌봄 일정이 등록', message.notification.body)


if __name__ == '__main__': unittest.main()
