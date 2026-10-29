"""실제 메시지·FCM을 만들지 않는 읽음·큐·권한 회귀 검증."""
import unittest
from unittest.mock import MagicMock, patch
from fastapi import HTTPException
from fastapi.testclient import TestClient
from python.main import app
from python.features.chats import router,read_status,push_outbox
from python.features.notifications import push
from python.features.schedules import reminder_worker


class ChatReadTests(unittest.TestCase):
    def test_read_requires_current_membership_and_message_in_same_room(self):
        for rows,expected in [([None],403),([{},None],403),([{},dict(participate_seq=2),None],422)]:
            c=MagicMock();q=c.cursor.return_value.__enter__.return_value
            q.fetchone.side_effect=rows
            with patch.object(read_status,'connect',return_value=c):
                with self.assertRaises(HTTPException) as error:read_status.mark_read('room','user',8)
            self.assertEqual(error.exception.status_code,expected)
            c.rollback.assert_called_once();c.commit.assert_not_called();c.close.assert_called_once()

    def test_mark_read_uses_monotonic_cursor_and_own_participation(self):
        c=MagicMock();q=c.cursor.return_value.__enter__.return_value
        q.fetchone.side_effect=[{},dict(participate_seq=2),dict(chat_seq=8),dict(last_read_chat_seq=12)]
        with patch.object(read_status,'connect',return_value=c):
            self.assertEqual(read_status.mark_read('room','user',8),{'last_read_chat_seq':12})
        sql=' '.join(call.args[0] for call in q.execute.call_args_list)
        self.assertIn('GREATEST(last_read_chat_seq,VALUES(last_read_chat_seq))',sql)
        self.assertIn('p.left_at IS NULL',sql);self.assertIn('p.is_active=1',sql)
        c.commit.assert_called_once()

    def test_unread_excludes_self_deleted_and_ended_membership(self):
        c=MagicMock();q=c.cursor.return_value.__enter__.return_value
        q.fetchall.return_value=[dict(family_room_id='room',unread_count=3)]
        with patch.object(read_status,'connect',return_value=c):
            self.assertEqual(read_status.unread_counts('verified'),{'room':3})
        sql,params=q.execute.call_args.args
        for value in ['m.user_id<>p.user_id','m.live_chat_deleted_at IS NULL','p.left_at IS NULL',
                      'f.family_room_deleted_at IS NULL','m.chat_seq>COALESCE(r.last_read_chat_seq,0)']:
            self.assertIn(value,sql)
        self.assertEqual(params,('verified',))

    def test_new_participation_initializes_at_current_latest_message(self):
        q=MagicMock();read_status.initialize(q,9,'room')
        sql,params=q.execute.call_args.args
        self.assertIn('COALESCE(MAX(chat_seq),0)',sql)
        self.assertEqual(params,(9,'room'))

    def test_endpoints_use_verified_identity_and_reject_bad_input(self):
        app.dependency_overrides[router.get_current_user_id]=lambda:'verified'
        try:
            with TestClient(app) as client,patch.object(read_status,'unread_counts',return_value={'room':2}) as count, \
                 patch.object(read_status,'mark_read',return_value={'last_read_chat_seq':7}) as mark:
                self.assertEqual(client.get('/chats/unread').json(),{'counts':{'room':2}})
                count.assert_called_once_with('verified')
                self.assertEqual(client.post('/chats/read',json={'family_room_id':'room','chat_seq':7}).status_code,200)
                mark.assert_called_once_with('room','verified',7)
                self.assertEqual(client.post('/chats/read',json={'family_room_id':'room','chat_seq':True}).status_code,422)
        finally:app.dependency_overrides.clear()


class ChatOutboxSaveTests(unittest.TestCase):
    def test_message_and_queue_commit_together_and_duplicate_never_requeues(self):
        from python.tests.test_chats import row,MESSAGE
        from pymysql import OperationalError
        for duplicate,failed in [(False,False),(True,False),(False,True)]:
            c=MagicMock();q=c.cursor.return_value.__enter__.return_value
            saved={**row(),'live_chat_deleted_at':None,'image_digest':None}
            q.fetchone.side_effect=[{'participate_seq':1},saved] if duplicate else [{'participate_seq':1},None,saved]
            def execute(sql,args):
                if failed and 'INSERT INTO chat_push_outbox' in sql:raise OperationalError('queue failed')
            q.execute.side_effect=execute
            with patch.object(router,'connect',return_value=c):
                if failed:
                    with self.assertRaises(HTTPException):router._save('room-a','db-user',router.MessageCreate(**MESSAGE))
                    c.rollback.assert_called_once();c.commit.assert_not_called()
                else:
                    _,again=router._save('room-a','db-user',router.MessageCreate(**MESSAGE))
                    self.assertEqual(again,duplicate);c.commit.assert_called_once()
            queues=[call for call in q.execute.call_args_list if 'INSERT INTO chat_push_outbox' in call.args[0]]
            self.assertEqual(len(queues),0 if duplicate else 1)


class ChatPushTests(unittest.TestCase):
    def test_rechecks_read_delete_membership_and_sender_before_send(self):
        c=MagicMock();q=c.cursor.return_value.__enter__.return_value
        event=dict(chat_seq=7,family_room_id='room',user_id='sender')
        q.fetchone.return_value=None
        self.assertIsNone(push_outbox.visible_chat(c,'receiver',event))
        sql,params=q.execute.call_args.args
        for value in ['p.left_at IS NULL','m.live_chat_deleted_at IS NULL','m.user_id<>%s',
                      'COALESCE(r.last_read_chat_seq,0)<m.chat_seq','p.joined_at<=m.sent_at']:
            self.assertIn(value,sql)
        self.assertEqual(params,('receiver',7,'room','sender','receiver'))
        q.fetchone.return_value={'chat_seq':7}
        self.assertEqual(push_outbox.visible_chat(c,'receiver',event),{'notification_type':'chat_message'})

    def test_claim_is_locked_and_lease_token_fences_late_completion(self):
        c=MagicMock();q=c.cursor.return_value.__enter__.return_value
        q.fetchone.return_value=dict(chat_seq=7,family_room_id='room',user_id='sender',attempts=0)
        with patch.object(push_outbox,'connect',return_value=c):
            job=push_outbox.claim_job()
        self.assertEqual(job['attempts'],1)
        self.assertEqual(len(job['lease_token']),32)
        self.assertIn('FOR UPDATE SKIP LOCKED',q.execute.call_args_list[0].args[0])
        with patch.object(push_outbox,'connect',return_value=c):push_outbox.finish_job(job,False)
        self.assertIn('AND lease_token=%s',q.execute.call_args.args[0])
        self.assertEqual(q.execute.call_args.args[1][0],'pending')

    def test_chat_reuses_delivery_without_creating_firestore_inbox_event(self):
        c=MagicMock();q=c.cursor.return_value.__enter__.return_value
        q.fetchall.return_value=[{'user_id':'receiver'}]
        job=dict(chat_seq=7,family_room_id='room',user_id='sender')
        with patch.object(push_outbox,'connect',return_value=c),patch.object(push_outbox,'dispatch_event',return_value=True) as send:
            self.assertTrue(push_outbox.process_job(job))
        kwargs=send.call_args.kwargs
        self.assertFalse(kwargs['finish_event'])
        self.assertEqual(send.call_args.args[1]['recipient_ids'],['receiver'])
        self.assertIn('p.user_id<>%s',q.execute.call_args.args[0])

    def test_worker_retries_transient_failure_and_caps_attempts(self):
        job=dict(chat_seq=7,family_room_id='room',user_id='sender',attempts=5,lease_token='token')
        with patch.object(push_outbox,'claim_job',side_effect=[job,None]), \
             patch.object(push_outbox,'process_job',side_effect=ValueError('offline')), \
             patch.object(push_outbox,'finish_job') as finish:
            self.assertEqual(push_outbox.check_chat_pushes(),1)
        finish.assert_called_once_with(job,False)
        c=MagicMock();q=c.cursor.return_value.__enter__.return_value
        with patch.object(push_outbox,'connect',return_value=c):push_outbox.finish_job(job,False)
        self.assertEqual(q.execute.call_args.args[1][0],'failed')

    def test_chat_fcm_contains_route_but_not_message_body_and_groups_by_room(self):
        with patch.object(push,'get_firebase_app'),patch.object(push.messaging,'send') as send:
            for seq in [7,8]:push.send_message('fid','uid',f'chat_{seq}',notification_type='chat_message',family_room_id='room',chat_seq=seq)
        messages=[call.args[0] for call in send.call_args_list]
        self.assertEqual(messages[0].android.notification.tag,messages[1].android.notification.tag)
        self.assertEqual(messages[0].data['family_room_id'],'room')
        self.assertEqual(messages[0].data['chat_seq'],'7')
        self.assertNotIn('chat_content',messages[0].data)

    def test_schedule_firestore_failure_does_not_stop_mysql_chat_queue(self):
        with patch.object(reminder_worker.logging,'basicConfig'), \
             patch.object(reminder_worker,'check_reminders',return_value=0), \
             patch.object(reminder_worker,'check_push_notifications',side_effect=ValueError('offline')), \
             patch.object(reminder_worker,'check_chat_pushes') as chat, \
             patch('sys.argv',['worker','--once']):
            reminder_worker.main()
        chat.assert_called_once()

if __name__=='__main__':unittest.main()
