"""외부 MySQL·Firestore·FCM 호출 없이 수신자와 재발행/접근 규칙을 확인한다."""
import unittest
from unittest.mock import MagicMock, patch
from python.features.notifications import space_events as events
from python.features.notifications import store
from python.features.schedules.notification_router import _visible, visible_v2


class SpaceEventsTest(unittest.TestCase):
    def connection(self):
        conn = MagicMock()
        conn.cursor.return_value.__enter__.return_value = self.cursor = MagicMock()
        return conn

    def test_recipients_exclude_actor_except_leave(self):
        for kind in events.TITLES:
            with self.subTest(kind=kind):
                conn = self.connection()
                self.cursor.fetchall.return_value = [{'user_id': 'actor'}, {'user_id': 'other'}]
                with patch.object(store, 'collection') as collection:
                    events.prepare(conn, 'room', 'actor', kind, 1, target_id='actor')
                    payload = collection.return_value.document.return_value.create.call_args.args[0]
                self.assertEqual(payload['recipient_ids'], ['actor', 'other'] if kind == 'member_left' else ['other'])
                self.assertEqual(payload['status'], 'pending')
                self.assertTrue(store.supports_push(payload))

    def test_publish_once_does_not_requeue_published_event(self):
        for status in ('pending', 'published'):
            tx, ref = MagicMock(), MagicMock()
            ref.get.return_value.to_dict.return_value = {'status': status}
            self.assertTrue(events._publish_once(tx, ref))
            self.assertEqual(tx.update.call_count, int(status == 'pending'))

    def test_departed_target_can_read_notice_without_room_access(self):
        for kind in ('member_left', 'member_removed'):
            conn = self.connection()
            self.cursor.fetchone.return_value = None
            event = dict(notification_id='space_1', notification_type=kind, family_room_id='r',
                         target_id='target', recipient_ids=['target', 'other'], status='published', created_at='now')
            with patch.object(store, 'inbox_state', return_value={}):
                self.assertIsNotNone(visible_v2(conn, 'target', event))
                self.assertIsNone(_visible(conn, 'other', event))
                self.assertIsNone(_visible(conn, 'outsider', event))

    def test_personal_delete_hides_space_event(self):
        conn = self.connection()
        self.cursor.fetchone.return_value = {'care_recipient_name': '가족'}
        event = dict(notification_id='space_1', notification_type='memo_created', family_room_id='r', created_at='now')
        with patch.object(store, 'inbox_state', return_value={'deleted_at': 'now'}):
            self.assertIsNone(events.visible(conn, 'member', event))

    def test_rollback_source_is_not_published(self):
        conn = self.connection()
        self.cursor.fetchone.return_value = None
        with patch.object(events, 'connect', return_value=conn), patch.object(store, 'get_event', return_value={
                'notification_type': 'memo_created', 'source_id': 'missing', 'family_room_id': 'r'}), patch.object(store, 'collection') as collection:
            self.assertFalse(events.publish('space_1'))
            collection.assert_not_called()
        conn.close.assert_called_once()

    def test_publish_failure_does_not_fail_committed_operation(self):
        with patch.object(events, 'publish', side_effect=RuntimeError('offline')):
            events.publish_safely('space_1')


class MemoNotificationHookTest(unittest.TestCase):
    def test_text_and_photo_create_prepare_before_commit_publish_after(self):
        from python.features.memos import router as memos
        for image in (None, b'photo'):
            with self.subTest(photo=image is not None):
                conn = MagicMock()
                cursor = conn.cursor.return_value.__enter__.return_value
                cursor.fetchone.return_value = {'participate_seq': 1}
                order = []
                conn.commit.side_effect = lambda: order.append('commit')
                with patch.object(memos, 'connect', return_value=conn), patch.object(events, 'prepare', side_effect=lambda *a: order.append('prepare') or 'event') as prepare, patch.object(events, 'publish_safely', side_effect=lambda *a: order.append('publish')):
                    result = memos._insert_memo(memos.MemoCreate(family_room_id='room', memo_content='hello'), 'actor', image)
                self.assertEqual(order, ['prepare', 'commit', 'publish'])
                prepare.assert_called_once_with(conn, 'room', 'actor', 'memo_created', result['memo_id'])

    def test_update_does_not_emit_create_notification(self):
        from python.features.memos import router as memos
        conn = MagicMock()
        with patch.object(memos, 'connect', return_value=conn), patch.object(memos, '_lock_owned_memo'), patch.object(events, 'prepare') as prepare, patch.object(events, 'publish_safely') as publish:
            memos._update_memo(memos.MemoUpdate(family_room_id='room', memo_content='edit'), 'memo', 'actor')
        prepare.assert_not_called()
        publish.assert_not_called()
        conn.commit.assert_called_once()

    def test_failed_create_does_not_publish(self):
        from python.features.memos import router as memos
        import pymysql
        from fastapi import HTTPException
        conn = MagicMock()
        conn.cursor.return_value.__enter__.return_value.fetchone.return_value = {'participate_seq': 1}
        conn.commit.side_effect = pymysql.MySQLError('commit failed')
        with patch.object(memos, 'connect', return_value=conn), patch.object(events, 'prepare', return_value='event'), patch.object(events, 'publish_safely') as publish, patch.object(memos.logger, 'exception'):
            with self.assertRaises(HTTPException):
                memos._insert_memo(memos.MemoCreate(family_room_id='room', memo_content='hello'), 'actor')
        publish.assert_not_called()
        conn.rollback.assert_called_once()


if __name__ == '__main__':
    unittest.main()
