"""일정 삭제 권한·저장 실패·삭제 알림 접근·재시도를 실제 DB 없이 검증한다."""

from datetime import date, datetime
from unittest import TestCase
from unittest.mock import MagicMock, patch

from fastapi import FastAPI, HTTPException
from fastapi.testclient import TestClient
from pymysql import OperationalError

from python.features.auth.firebase_auth import require_firebase_user
from python.features.schedules import delete_schedule as deletion
from python.features.schedules import notification_router as notices
from python.features.schedules import reconfirm_expiry_worker as worker
from python.features.schedules import router as schedules
from python.features.schedules.reconfirm_expiry import get_expired_reconfirm_request
from python.features.schedules.urgent_reconfirm import get_urgent_unverified_request


STAMP = datetime(2026, 10, 27, 20, 0)
DELETED_AT = datetime(2026, 10, 27, 21, 0)
IDENTIFIER = 'schedule_deleted_7_42'
URL = '/schedules/schedule-notifications'


def schedule_row():
    return dict(
        schedule_seq=7, family_room_id='room', created_at=STAMP,
        deleted_at=None, history_seq=41, accepted_by='family',
        accepted_at=STAMP, schedule_date=date(2026, 10, 29),
        schedule_state='미완료', schedule_name='삭제 테스트',
        start_time='09:00:00', end_time='10:00:00', schedule_memo=None,
    )


def saved_deletion():
    return {
        **schedule_row(), 'history_seq': 42, 'deleted_at': DELETED_AT,
        'accepted_by': None, 'history_updated_at': DELETED_AT,
        'updated_at': DELETED_AT, 'changed_by': 'primary',
        'care_recipient_name': '대상자',
    }


def deletion_event():
    saved = saved_deletion()
    return dict(
        notification_id=IDENTIFIER, notification_type='schedule_deleted',
        status='published', schedule_seq=7, history_seq=42,
        family_room_id='room', recipient_ids=['primary', 'family'],
        schedule_created_at=str(STAMP), history_updated_at=str(DELETED_AT),
        created_at=DELETED_AT, deleted_at=str(DELETED_AT), deleted_by='primary',
        former_assignee_id='family', schedule_name=saved['schedule_name'],
        schedule_date=str(saved['schedule_date']), start_time=saved['start_time'],
        end_time=saved['end_time'], schedule_memo=None,
    )


class DeleteApiTests(TestCase):
    def setUp(self):
        app = FastAPI()
        app.include_router(schedules.router)
        app.dependency_overrides[schedules.get_current_user_id] = lambda: 'primary'
        self.app = app
        self.client = self.enterContext(TestClient(app))
        self.conn = MagicMock()
        self.cursor = self.conn.cursor.return_value.__enter__.return_value
        self.cursor.fetchone.side_effect = [
            {'family_room_id': 'room'}, {'is_representative': 1},
        ]
        self.connect = self.enterContext(patch.object(schedules, 'connect', return_value=self.conn))
        self.get = self.enterContext(patch.object(schedules, 'get_schedule_for_delete', return_value=schedule_row()))
        self.mark = self.enterContext(patch.object(schedules, 'mark_schedule_deleted', return_value=saved_deletion()))
        self.prepare = self.enterContext(patch.object(schedules, 'prepare_schedule_delete_notification'))
        self.publish = self.enterContext(patch.object(schedules, 'publish_schedule_delete_notification', return_value=True))

    def delete(self):
        return self.client.delete('/schedules/7', params={'family_room_id': 'room'})

    def test_requires_authentication_before_connecting(self):
        self.app.dependency_overrides.clear()
        self.assertEqual(self.delete().status_code, 401)
        self.connect.assert_not_called()

    def test_current_primary_required_before_mutation(self):
        self.cursor.fetchone.side_effect = [
            {'family_room_id': 'room'}, {'is_representative': 0},
        ]
        self.assertEqual(self.delete().status_code, 403)
        self.get.assert_not_called()
        self.mark.assert_not_called()
        self.conn.rollback.assert_called_once()
        self.conn.close.assert_called_once()

    def test_deleted_space_is_rejected_before_schedule_lookup(self):
        self.cursor.fetchone.side_effect = [None]
        self.assertEqual(self.delete().status_code, 403)
        self.get.assert_not_called()

    def test_assigned_schedule_commits_and_closes_before_publishing(self):
        order = []
        self.prepare.side_effect = lambda *args: order.append('prepare')
        self.conn.commit.side_effect = lambda: order.append('commit')
        self.conn.close.side_effect = lambda: order.append('close')
        self.publish.side_effect = lambda *args: order.append('publish') or True
        response = self.delete()
        self.assertEqual(response.status_code, 200)
        self.assertTrue(response.json()['deleted'])
        self.assertTrue(response.json()['changed'])
        self.assertEqual(order, ['prepare', 'commit', 'close', 'publish'])
        self.mark.assert_called_once_with(self.conn, schedule_row(), 'primary')

    def test_preparation_failure_rolls_back_without_publishing(self):
        self.prepare.side_effect = RuntimeError('private firestore failure')
        with self.assertLogs(schedules.logger, level='ERROR'):
            response = self.delete()
        self.assertEqual(response.status_code, 503)
        self.assertNotIn('private', response.text)
        self.conn.rollback.assert_called_once()
        self.conn.commit.assert_not_called()
        self.publish.assert_not_called()

    def test_publication_failure_keeps_committed_deletion(self):
        self.publish.side_effect = RuntimeError('offline')
        with self.assertLogs(schedules.logger, level='ERROR'):
            response = self.delete()
        self.assertEqual(response.status_code, 200)
        self.assertFalse(response.json()['notification_published'])
        self.conn.commit.assert_called_once()
        self.conn.rollback.assert_not_called()

    def test_repeated_delete_does_not_add_history(self):
        self.get.return_value = saved_deletion()
        response = self.delete()
        self.assertEqual(response.status_code, 200)
        self.assertFalse(response.json()['changed'])
        self.mark.assert_not_called()
        self.prepare.assert_not_called()
        self.conn.commit.assert_not_called()
        self.publish.assert_called_once_with(7, 42)

    def test_other_room_schedule_is_not_mutated(self):
        self.get.side_effect = HTTPException(404, '해당 돌봄 공간의 일정이 없습니다.')
        self.assertEqual(self.delete().status_code, 404)
        self.mark.assert_not_called()
        self.publish.assert_not_called()

    def test_commit_failure_never_publishes(self):
        self.conn.commit.side_effect = OperationalError(2006, 'private')
        with self.assertLogs(schedules.logger, level='ERROR'):
            self.assertEqual(self.delete().status_code, 503)
        self.conn.rollback.assert_called_once()
        self.publish.assert_not_called()

    def test_deleted_schedule_cannot_be_modified(self):
        self.cursor.fetchone.side_effect = [
            {'family_room_id': 'room'}, {'is_representative': 1}, None,
        ]
        response = self.client.put('/schedules/7', json={
            'family_room_id': 'room', 'schedule_date': '2026-10-29',
            'start_time': '09:00', 'end_time': '10:00',
        })
        self.assertEqual(response.status_code, 404)
        self.assertIn('deleted_at IS NULL', self.cursor.execute.call_args.args[0])
        self.conn.commit.assert_not_called()

    def test_deleted_schedule_cannot_be_accepted_or_reconfirmed(self):
        self.cursor.fetchone.side_effect = None
        self.cursor.fetchone.return_value = None
        for path, data in (
            ('/schedules/7/accept', None),
            ('/schedules/7/changes/41/respond', {'accepted': True}),
        ):
            with self.subTest(path=path):
                self.cursor.execute.reset_mock()
                response = self.client.post(path, json=data)
                self.assertEqual(response.status_code, 404)
                self.assertEqual(self.cursor.execute.call_count, 1)
                self.assertIn('deleted_at IS NULL', self.cursor.execute.call_args.args[0])
        self.conn.commit.assert_not_called()


class DeleteStorageTests(TestCase):
    def setUp(self):
        self.conn = MagicMock()
        self.cursor = self.conn.cursor.return_value.__enter__.return_value

    def test_assigned_and_unassigned_deletions_preserve_history_and_content(self):
        for assignee in ('family', None):
            with self.subTest(assignee=assignee):
                self.cursor.reset_mock()
                self.cursor.rowcount = 1
                self.cursor.lastrowid = 42
                self.cursor.fetchone.return_value = {'deleted_at': DELETED_AT}
                before = {**schedule_row(), 'accepted_by': assignee}
                after = deletion.mark_schedule_deleted(self.conn, before, 'primary')
                self.assertIsNone(after['accepted_by'])
                self.assertEqual(after['former_assignee_id'], assignee)
                self.assertEqual(after['schedule_date'], before['schedule_date'])
                self.assertEqual(before['deleted_at'], None)
                update_sql = self.cursor.execute.call_args_list[0].args[0]
                self.assertIn('deleted_at = CURRENT_TIMESTAMP', update_sql)
                self.assertIn('accepted_by = NULL', update_sql)
                insert_sql, values = self.cursor.execute.call_args_list[1].args
                self.assertIn('INSERT INTO update_schedule', insert_sql)
                self.assertIn('NULL, NULL', insert_sql)
                self.assertEqual(values[3], 'primary')
                self.conn.commit.assert_not_called()

    def test_soft_deleted_record_cannot_create_another_history(self):
        self.assertIsNone(deletion.mark_schedule_deleted(self.conn, saved_deletion(), 'primary'))
        self.cursor.execute.assert_not_called()

    def test_changed_state_raises_conflict_before_history_insert(self):
        self.cursor.rowcount = 0
        with self.assertRaises(HTTPException) as caught:
            deletion.mark_schedule_deleted(self.conn, schedule_row(), 'primary')
        self.assertEqual(caught.exception.status_code, 409)
        self.assertEqual(self.cursor.execute.call_count, 1)

    def test_notification_preparation_freezes_all_current_family(self):
        self.cursor.fetchone.return_value = saved_deletion()
        self.cursor.fetchall.return_value = [{'user_id': 'primary'}, {'user_id': 'family'}]
        deleted = {**saved_deletion(), 'deleted_by': 'primary', 'former_assignee_id': 'family'}
        with patch.object(deletion, 'prepare_change') as prepare:
            deletion.prepare_schedule_delete_notification(self.conn, deleted)
        payload = prepare.call_args.args[0]
        self.assertEqual(payload['recipient_ids'], ['family', 'primary'])
        self.assertEqual(payload['former_assignee_id'], 'family')
        self.assertEqual(payload['notification_type'], 'schedule_deleted')
        sql = self.cursor.execute.call_args_list[1].args[0]
        self.assertIn('p.left_at IS NULL', sql)
        self.assertIn('u.withdrawn_at IS NULL', sql)
        self.conn.commit.assert_not_called()

    def test_rolled_back_deletion_cannot_publish(self):
        self.cursor.fetchone.return_value = None
        with patch.object(deletion, 'connect', return_value=self.conn), patch.object(
            deletion, 'get_event', return_value=deletion_event()
        ), patch.object(deletion, 'publish') as publish:
            self.assertFalse(deletion.publish_schedule_delete_notification(7, 42))
        publish.assert_not_called()
        self.conn.close.assert_called_once()

    def test_publication_checks_snapshot_and_keeps_stable_identifier(self):
        self.cursor.fetchone.return_value = saved_deletion()
        with patch.object(deletion, 'connect', return_value=self.conn), patch.object(
            deletion, 'get_event', return_value=deletion_event()
        ), patch.object(deletion, 'publish', return_value=True) as publish:
            self.assertTrue(deletion.publish_schedule_delete_notification(7, 42))
        publish.assert_called_once_with(IDENTIFIER, str(STAMP))

    def test_mismatched_snapshot_is_never_published(self):
        self.cursor.fetchone.return_value = saved_deletion()
        event = {**deletion_event(), 'end_time': '11:00:00'}
        with patch.object(deletion, 'connect', return_value=self.conn), patch.object(
            deletion, 'get_event', return_value=event
        ), patch.object(deletion, 'publish') as publish:
            self.assertFalse(deletion.publish_schedule_delete_notification(7, 42))
        publish.assert_not_called()


class DeletedNotificationTests(TestCase):
    def setUp(self):
        app = FastAPI()
        app.include_router(schedules.router)
        app.dependency_overrides[require_firebase_user] = lambda: {'uid': 'verified'}
        self.client = self.enterContext(TestClient(app))
        self.conn = MagicMock()
        self.cursor = self.conn.cursor.return_value.__enter__.return_value
        self.cursor.fetchone.return_value = saved_deletion()
        self.enterContext(patch.object(notices, 'connect', return_value=self.conn))
        self.enterContext(patch.object(notices, '_user_id', return_value='family'))
        self.enterContext(patch.object(notices.store, 'inbox_state', return_value={}))
        self.event = deletion_event()

    def test_committed_deletion_is_listed_with_snapshot(self):
        with patch.object(notices, 'list_notification_events', return_value=[self.event]):
            response = self.client.get(URL)
        self.assertEqual(response.status_code, 200)
        row = response.json()['results'][0]
        self.assertTrue(row['deleted'])
        self.assertEqual(row['notification_id'], IDENTIFIER)
        self.assertEqual(row['schedule_name'], '삭제 테스트')

    def test_deletion_can_be_marked_read(self):
        with patch.object(notices.store, 'get_event', return_value=self.event), patch.object(
            notices.store, 'mark_read', return_value=DELETED_AT
        ) as mark:
            response = self.client.post(f'{URL}/{IDENTIFIER}/read')
        self.assertEqual(response.status_code, 200)
        mark.assert_called_once_with(IDENTIFIER, 'family')

    def test_deletion_cannot_open_schedule(self):
        with patch.object(notices.store, 'get_event', return_value=self.event):
            response = self.client.get(f'{URL}/{IDENTIFIER}/schedule')
        self.assertEqual(response.status_code, 410)
        self.assertEqual(response.json()['detail'], '삭제된 일정입니다.')

    def test_pending_and_nonrecipient_events_are_hidden_before_db_query(self):
        for changes in ({'status': 'pending'}, {'recipient_ids': ['someone-else']}):
            with self.subTest(changes=changes):
                self.assertIsNone(notices._visible(self.conn, 'family', {**self.event, **changes}))
        self.cursor.execute.assert_not_called()

    def test_departed_family_or_deleted_space_cannot_read_notice(self):
        self.cursor.fetchone.return_value = None
        with patch.object(notices.store, 'get_event', return_value=self.event), patch.object(
            notices.store, 'mark_read'
        ) as mark:
            self.assertEqual(self.client.post(f'{URL}/{IDENTIFIER}/read').status_code, 404)
        mark.assert_not_called()
        sql = self.cursor.execute.call_args.args[0]
        for clause in ('p.left_at IS NULL', 'u.withdrawn_at IS NULL', 'f.family_room_deleted_at IS NULL'):
            self.assertIn(clause, sql)

    def test_snapshot_or_identifier_mismatch_is_hidden(self):
        for changes in (
            {'notification_id': 'schedule_deleted_7_99'},
            {'schedule_created_at': 'other'}, {'deleted_at': 'other'},
            {'history_updated_at': 'other'}, {'schedule_name': 'other'},
            {'deleted_by': 'other'}, {'start_time': '08:00:00'},
        ):
            with self.subTest(changes=changes):
                self.assertIsNone(notices._visible(self.conn, 'family', {**self.event, **changes}))

    def test_old_nondeletion_notification_stays_hidden_for_deleted_schedule(self):
        self.cursor.fetchone.return_value = None
        event = {**self.event, 'notification_type': 'schedule_reconfirm'}
        self.assertIsNone(notices._visible(self.conn, 'family', event))
        self.assertIn('s.deleted_at IS NULL', self.cursor.execute.call_args.args[0])


class DeletedWorkerTests(TestCase):
    def snapshots(self, *identifiers):
        return [MagicMock(id=identifier, to_dict=MagicMock(return_value={
            **deletion_event(), 'status': 'pending',
        })) for identifier in identifiers]

    def test_pending_deletion_retries_with_same_history(self):
        collection = MagicMock()
        collection.where.return_value.stream.return_value = self.snapshots(IDENTIFIER)
        with patch.object(worker, 'collection', return_value=collection), patch.object(
            worker, 'publish_schedule_delete_notification', return_value=True
        ) as publish:
            worker.retry_pending_notifications()
        publish.assert_called_once_with(7, 42)

    def test_one_failure_does_not_stop_next_deletion_retry(self):
        collection = MagicMock()
        collection.where.return_value.stream.return_value = self.snapshots(IDENTIFIER, IDENTIFIER)
        with patch.object(worker, 'collection', return_value=collection), patch.object(
            worker, 'publish_schedule_delete_notification', side_effect=[RuntimeError('offline'), True]
        ) as publish:
            with self.assertLogs(worker.logger, level='ERROR'):
                worker.retry_pending_notifications()
        self.assertEqual(publish.call_count, 2)

    def test_noncanonical_document_does_not_trigger_another_notification(self):
        collection = MagicMock()
        collection.where.return_value.stream.return_value = self.snapshots('wrong-document')
        with patch.object(worker, 'collection', return_value=collection), patch.object(
            worker, 'publish_schedule_delete_notification'
        ) as publish:
            worker.retry_pending_notifications()
        publish.assert_not_called()

    def test_deleted_schedule_does_not_expire_or_create_urgent_notice(self):
        for function in (get_expired_reconfirm_request, get_urgent_unverified_request):
            with self.subTest(function=function.__name__):
                conn = MagicMock()
                cursor = conn.cursor.return_value.__enter__.return_value
                cursor.fetchone.side_effect = [{'family_room_id': 'room'}, None]
                self.assertIsNone(function(conn, 7, 'room'))
                self.assertIn('deleted_at IS NULL', cursor.execute.call_args.args[0])
                conn.commit.assert_not_called()

