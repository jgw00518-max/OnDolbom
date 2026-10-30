"""실제 DB·Firestore·FCM 없이 공간 삭제 알림의 권한·재시도·API를 검증한다."""
import unittest
from unittest.mock import MagicMock, patch

from fastapi import FastAPI, HTTPException
from fastapi.testclient import TestClient

from python.features.family_room import delete_notifications as notice
from python.features.notifications import store, push
from python.features.schedules import notification_router as api
from python.features.schedules import reconfirm_expiry_worker as worker
from python.features.auth.firebase_auth import require_firebase_user
from python.features.activity import router as activity

CREATED, DELETED = '2026-10-01 10:00:00', '2026-10-30 10:00:00'
ROOM = dict(family_room_id='room', created_at=CREATED,
            family_room_deleted_at=DELETED, care_recipient_name='가족')


def event(**changes):
    return dict(notification_id=notice.notification_id('room', CREATED, DELETED),
                notification_type=notice.KIND, family_room_id='room',
                room_created_at=CREATED, room_deleted_at=DELETED,
                care_recipient_name='가족', actor_id='guardian', recipient_ids=['family'],
                status='published', created_at='now', **changes)


class RoomDeletionNoticeTests(unittest.TestCase):
    def setUp(self):
        self.conn = MagicMock()
        self.cursor = self.conn.cursor.return_value.__enter__.return_value
        self.receipt = self.enterContext(patch.object(store, 'inbox_state', return_value={}))

    def test_prepare_captures_only_active_nonwithdrawn_members_excluding_actor(self):
        self.cursor.fetchall.return_value = [{'user_id': 'family'}]
        with patch.object(store, 'collection') as collection, \
             patch.object(notice.firestore, 'transactional', side_effect=lambda f: f):
            ref = collection.return_value.document.return_value
            ref.get.return_value.exists = False
            notice.prepare_notification(self.conn, 'room', ROOM, DELETED, 'guardian')
        sql, parameters = self.cursor.execute.call_args.args
        for condition in ('p.is_active=1', 'p.left_at IS NULL', 'u.withdrawn_at IS NULL', 'p.user_id<>%s'):
            self.assertIn(condition, sql)
        self.assertEqual(parameters, ('room', 'guardian'))
        payload = ref._client.transaction.return_value.create.call_args.args[1]
        self.assertEqual(payload['recipient_ids'], ['family'])
        self.assertEqual(payload['status'], 'pending')

    def test_prepare_failure_is_not_success(self):
        self.cursor.fetchall.return_value = []
        with patch.object(store, 'collection', side_effect=ValueError('private')):
            with self.assertRaises(HTTPException) as caught:
                notice.prepare_notification(self.conn, 'room', ROOM, DELETED, 'guardian')
        self.assertEqual(caught.exception.status_code, 503)
        self.assertNotIn('private', caught.exception.detail)

    def test_deleted_space_notice_is_visible_but_never_reads_schedule_data(self):
        self.cursor.fetchone.side_effect = [ROOM, {'participate_seq': 1}]
        result = api.visible_v2(self.conn, 'family', event())
        self.assertEqual(result['notification_type'], notice.KIND)
        self.assertEqual(result['room_deleted_at'], DELETED)
        sql = ' '.join(call.args[0] for call in self.cursor.execute.call_args_list)
        self.assertNotIn('create_schedule', sql)
        self.assertIn('p.joined_at<=%s', sql)
        self.assertIn('u.withdrawn_at IS NULL', sql)

    def test_foreign_actor_pending_and_ended_membership_cannot_read(self):
        for user, status in [('outsider', 'published'), ('guardian', 'published'), ('family', 'pending')]:
            saved = event()
            saved['status'] = status
            self.assertIsNone(api.visible_v2(self.conn, user, saved))
        self.cursor.execute.assert_not_called()
        self.cursor.fetchone.side_effect = [ROOM, None]
        self.assertIsNone(api.visible_v2(self.conn, 'family', event()))

    def test_wrong_deletion_version_or_personally_hidden_notice_is_invisible(self):
        for deleted in [None, 'another-version']:
            self.cursor.fetchone.side_effect = None
            self.cursor.fetchone.return_value = {**ROOM, 'family_room_deleted_at': deleted}
            self.assertIsNone(api.visible_v2(self.conn, 'family', event()))
        self.cursor.fetchone.side_effect = [ROOM, {'participate_seq': 1}]
        self.receipt.return_value = {'deleted_at': 'hidden'}
        self.assertIsNone(api.visible_v2(self.conn, 'family', event()))

    def test_publish_is_idempotent_and_does_not_reset_receipts_or_queue(self):
        transaction, ref = MagicMock(), MagicMock()
        saved = event()
        ref.get.return_value.exists = True
        ref.get.return_value.to_dict.return_value = saved
        self.assertTrue(notice._publish(transaction, ref, saved))
        transaction.update.assert_not_called()
        saved['status'] = 'pending'
        self.assertTrue(notice._publish(transaction, ref, saved))
        self.assertTrue(transaction.update.call_args.args[1]['push_pending'])
        transaction.reset_mock()
        notice._prepare(transaction, ref, saved)
        transaction.create.assert_not_called()
        transaction.update.assert_not_called()

    def test_rolled_back_room_deletion_cannot_be_published_by_retry(self):
        self.cursor.fetchone.return_value = {**ROOM, 'family_room_deleted_at': None}
        with patch.object(notice, 'connect', return_value=self.conn), \
             patch.object(store, 'get_event', return_value=event()), \
             patch.object(store, 'collection') as collection:
            self.assertFalse(notice.publish_notification(event()['notification_id']))
        collection.assert_not_called()
        self.conn.close.assert_called_once()

    def test_fresh_retry_in_same_second_refreshes_only_orphan_pending_recipients(self):
        transaction, ref = MagicMock(), MagicMock()
        old = {**event(), 'status': 'pending'}
        fresh = {**old, 'actor_id': 'another-guardian', 'recipient_ids': ['new-family']}
        ref.get.return_value.exists = True
        ref.get.return_value.to_dict.return_value = old
        notice._prepare(transaction, ref, fresh)
        self.assertEqual(transaction.update.call_args.args[1],
                         {'actor_id': 'another-guardian', 'recipient_ids': ['new-family']})
        transaction.reset_mock()
        old['status'] = 'published'
        notice._prepare(transaction, ref, fresh)
        transaction.update.assert_not_called()

    def test_committed_deletion_is_published_once_and_repeated_publication_preserves_queue(self):
        saved = {**event(), 'status': 'pending'}
        self.cursor.fetchone.return_value = ROOM
        with patch.object(notice, 'connect', return_value=self.conn), \
             patch.object(store, 'get_event', return_value=saved), \
             patch.object(store, 'collection') as collection, \
             patch.object(notice.firestore, 'transactional', side_effect=lambda f: f):
            ref = collection.return_value.document.return_value
            ref.get.return_value.exists = True
            ref.get.return_value.to_dict.return_value = saved
            self.assertTrue(notice.publish_notification(saved['notification_id']))
            transaction = ref._client.transaction.return_value
            self.assertTrue(transaction.update.call_args.args[1]['push_pending'])
            transaction.reset_mock()
            saved['status'] = 'published'
            self.assertTrue(notice.publish_notification(saved['notification_id']))
            transaction.update.assert_not_called()
        self.assertEqual(self.conn.close.call_count, 2)

    def test_worker_recovers_pending_room_notice_without_scheduling_new_worker(self):
        snapshot = MagicMock()
        snapshot.id = event()['notification_id']
        snapshot.to_dict.return_value = {**event(), 'status': 'pending'}
        with patch.object(worker, 'collection') as collection, \
             patch.object(worker, 'publish_room_deletion', return_value=True) as publish:
            collection.return_value.where.return_value.stream.return_value = [snapshot]
            worker.retry_pending_notifications()
        publish.assert_called_once_with(snapshot.id)

    def test_push_has_generic_text_without_care_recipient_name(self):
        self.assertTrue(store.supports_push(event()))
        with patch.object(push, 'get_firebase_app'), patch.object(push.messaging, 'send') as send:
            push.send_message('fid', 'uid', 'event', notification_type=notice.KIND)
        message = send.call_args.args[0]
        self.assertIn('돌봄 공간이 삭제', message.notification.body)
        self.assertEqual(message.data['type'], notice.KIND)
        self.assertEqual(set(message.data), {'notification_id', 'user_uid', 'type'})


class RoomDeletionNoticeApiTests(unittest.TestCase):
    def setUp(self):
        app = FastAPI()
        app.include_router(api.router)
        app.dependency_overrides[require_firebase_user] = lambda: {'uid': 'verified'}
        self.client = self.enterContext(TestClient(app))
        conn = MagicMock()
        cursor = conn.cursor.return_value.__enter__.return_value

        def query(sql, values):
            cursor.fetchone.return_value = ROOM if 'FROM family_room' in sql else {'participate_seq': 1}

        cursor.execute.side_effect = query
        self.conn = conn
        self.enterContext(patch.object(api, 'connect', return_value=conn))
        self.enterContext(patch.object(api, '_user_id', return_value='family'))
        self.enterContext(patch.object(api, 'list_notification_events', return_value=[event()]))
        self.enterContext(patch.object(store, 'get_event', return_value=event()))
        self.enterContext(patch.object(store, 'inbox_state', return_value={}))
        self.enterContext(patch.object(api.badge_cache, 'invalidate'))

    def test_list_detail_read_and_personal_deletion_share_recipient_validation(self):
        root = '/schedule-notifications'
        identifier = event()['notification_id']
        self.assertEqual(self.client.get(root + '?scope=v2').json()['results'][0]['notification_type'], notice.KIND)
        self.assertEqual(self.client.get(f'{root}/{identifier}/room').status_code, 200)
        self.assertEqual(self.client.get(f'{root}/{identifier}/schedule').status_code, 410)
        with patch.object(store, 'mark_read', return_value='read') as read:
            self.assertEqual(self.client.post(f'{root}/{identifier}/read').json()['read_at'], 'read')
        read.assert_called_once_with(identifier, 'family')
        with patch.object(store, 'hide_many') as hide:
            self.assertEqual(self.client.delete(f'{root}/{identifier}').status_code, 200)
        hide.assert_called_once_with([identifier], 'family')
        with patch.object(store, 'hide_many') as hide:
            self.assertEqual(self.client.delete(root).json()['count'], 1)
        hide.assert_called_once_with([identifier], 'family')

    def test_nonrecipient_cannot_read_room_notice(self):
        with patch.object(api, '_user_id', return_value='outsider'):
            identifier = event()['notification_id']
            self.assertEqual(self.client.get(f'/schedule-notifications/{identifier}/room').status_code, 404)

    def test_badge_and_read_all_use_the_same_deleted_space_visibility(self):
        with patch.object(activity, 'list_notification_events', return_value=[event()]):
            self.assertEqual(activity.notification_count(self.conn, 'family'), 1)
            with patch.object(store, 'inbox_state', return_value={'read_at': 'read'}):
                self.assertEqual(activity.notification_count(self.conn, 'family'), 0)
            with patch.object(store, 'inbox_state', return_value={'deleted_at': 'hidden'}):
                self.assertEqual(activity.notification_count(self.conn, 'family'), 0)
        with patch.object(store, 'mark_many_read') as read:
            result = self.client.post('/schedule-notifications/read-all')
            self.assertEqual(result.json()['count'], 1)
        read.assert_called_once_with([event()['notification_id']], 'family')
