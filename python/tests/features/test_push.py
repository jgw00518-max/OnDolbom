import unittest
from datetime import datetime, timedelta, timezone
from unittest.mock import MagicMock, patch
from fastapi import FastAPI, HTTPException
from fastapi.testclient import TestClient
from python.features.notifications import push, store


class PushTests(unittest.TestCase):
    def payload(self, generation=2):
        return push.Registration(installation_id='a'*32, secret='b'*64, generation=generation, fid='private-fid'*10)

    def test_requires_auth_before_database(self):
        app = FastAPI()
        app.include_router(push.router)
        with patch.object(push, 'connect') as connect, TestClient(app) as client:
            self.assertEqual(client.post('/push/devices', json={}).status_code, 401)
            connect.assert_not_called()

    def test_binding_ownership_and_stale_generation_cannot_overwrite_account(self):
        ref, transaction = MagicMock(), MagicMock()
        ref.get.return_value.exists = True
        ref.get.return_value.to_dict.return_value = dict(secret_hash=push.digest('b'*64), generation=3, user_uid='new')
        for generation in [2, 3]:
            with self.assertRaises(HTTPException):
                push._bind(transaction, ref, self.payload(generation), 'old', 'mysql', True)
        transaction.set.assert_not_called()
        push._bind(transaction, ref, self.payload(4), 'new', 'mysql-new', True)
        self.assertEqual(transaction.set.call_args.args[1]['user_uid'], 'new')
        self.assertNotIn('secret', transaction.set.call_args.args[1])
        wrong = self.payload(5).model_copy(update={'secret': push.SecretStr('c'*64)})
        with self.assertRaises(HTTPException):
            push._bind(transaction, ref, wrong, 'new', 'mysql-new', True)

    def test_claim_keeps_sent_and_active_leases_and_caps_retries(self):
        now = datetime.now(timezone.utc)
        ref, transaction = MagicMock(), MagicMock()
        ref.get.return_value.exists = True
        for old in [dict(status='sent'), dict(status='processing', lease_until=now+timedelta(minutes=1))]:
            ref.get.return_value.to_dict.return_value = old
            self.assertFalse(push._claim(transaction, ref, now))
        transaction.set.assert_not_called()
        ref.get.return_value.to_dict.return_value = dict(status='pending', attempts=5)
        self.assertFalse(push._claim(transaction, ref, now))
        transaction.update.assert_called_once()

    def test_registration_publication_enqueues_once_and_republication_does_not(self):
        ref, transaction = MagicMock(), MagicMock()
        ref.get.return_value.exists = True
        ref.get.return_value.to_dict.return_value = dict(status='pending', schedule_created_at='created')
        self.assertTrue(store._publish(transaction, ref, 'created'))
        self.assertTrue(transaction.update.call_args.args[1]['push_pending'])
        transaction.reset_mock()
        ref.get.return_value.to_dict.return_value = dict(status='published', schedule_created_at='created')
        self.assertTrue(store._publish(transaction, ref, 'created'))
        transaction.update.assert_not_called()

    def test_delivery_checks_current_access_and_failure_does_not_change_inbox(self):
        for visible, failed in [(True, False), (False, False), (True, True)]:
            database, connection = MagicMock(), MagicMock()
            device = dict(enabled=True, expires_at=datetime.now(timezone.utc)+timedelta(days=1), generation=2,
                          user_uid='uid', user_id='mysql', fid='private-fid')
            snapshot = MagicMock(id='device')
            snapshot.to_dict.return_value = device
            snapshot.reference.get.return_value.to_dict.return_value = device
            devices, deliveries = MagicMock(), MagicMock()
            devices.where.return_value.stream.return_value = [snapshot]
            delivery = deliveries.document.return_value
            database.collection.side_effect = lambda name: devices if name == 'push_devices' else deliveries
            connection.cursor.return_value.__enter__.return_value.fetchone.return_value = {'user_id': 'mysql'}
            with patch.object(push, 'db', return_value=database), patch.object(push, 'connect', return_value=connection), \
                 patch.object(push.firestore, 'transactional', return_value=lambda *args: 1), \
                 patch.object(push, '_visible', return_value={'notification_type': 'schedule_declined'} if visible else None), \
                 patch.object(push, 'send_message', side_effect=ValueError('offline') if failed else None) as send, \
                 patch.object(push.store, 'collection') as events:
                push.dispatch_event('7', {'recipient_ids': ['mysql'], 'notification_type': 'schedule_recruitment'})
            self.assertEqual(send.call_count, int(visible))
            if visible:
                self.assertEqual(send.call_args.kwargs['notification_type'], 'schedule_declined')
            status = delivery.update.call_args.args[0]['status']
            self.assertEqual(status, 'pending' if failed else 'sent' if visible else 'skipped')
            if failed:
                events.assert_not_called()
            connection.commit.assert_not_called()
            connection.close.assert_called_once()

    def test_message_uses_channel_and_minimal_payload(self):
        with patch.object(push, 'get_firebase_app', return_value='app'), patch.object(push.messaging, 'send') as send:
            push.send_message('private-token', 'uid', '7')
        message = send.call_args.args[0]
        self.assertEqual(message.android.notification.channel_id, 'ondolbom_updates')
        self.assertEqual(message.data['user_uid'], 'uid')
        self.assertNotIn('schedule_memo', message.data)

    def test_only_enabled_types_enqueue_on_first_publication(self):
        for kind in ('schedule_created', 'schedule_changed', 'schedule_deleted',
                     'schedule_reconfirm', 'schedule_accepted', 'schedule_reconfirmed',
                     'schedule_recruitment', 'schedule_reminder'):
            with self.subTest(kind=kind):
                ref, transaction = MagicMock(), MagicMock()
                ref.get.return_value.exists = True
                ref.get.return_value.to_dict.return_value = dict(
                    status='pending', schedule_created_at='stamp', notification_type=kind)
                store._publish(transaction, ref, 'stamp')
                values = transaction.update.call_args.args[1]
                self.assertEqual(values.get('push_pending', False),
                                 kind in {'schedule_created', 'schedule_changed', 'schedule_deleted', 'schedule_reconfirm',
                                          'schedule_accepted', 'schedule_reconfirmed', 'schedule_recruitment'})

    def test_change_and_delete_messages_keep_private_details_out(self):
        for kind, word in [('schedule_changed', '변경'), ('schedule_deleted', '삭제'),
                           ('schedule_reconfirm', '재수락'), ('schedule_accepted', '수락'),
                           ('schedule_reconfirmed', '재수락'), ('schedule_declined', '거절'),
                           ('schedule_recruitment', '모집')]:
            with self.subTest(kind=kind), patch.object(push, 'get_firebase_app'), \
                 patch.object(push.messaging, 'send') as send:
                push.send_message('fid', 'uid', 'event', notification_type=kind)
                message = send.call_args.args[0]
                self.assertEqual(message.data['type'], kind)
                self.assertIn(word, message.notification.body)
                self.assertEqual(set(message.data), {'notification_id', 'user_uid', 'type'})

    def test_automatic_recruitment_is_not_pushed(self):
        self.assertFalse(store.supports_push(dict(notification_type='schedule_recruitment', request_history_seq=1)))
        self.assertTrue(store.supports_push(dict(notification_type='schedule_recruitment')))
        self.assertFalse(store.supports_push(dict(notification_type='schedule_reminder')))

    def test_self_test_rejects_other_accounts_expired_and_stale_bindings(self):
        now = datetime.now(timezone.utc)
        current = dict(user_uid='uid', user_id='mysql', secret_hash=push.digest('b'*64),
                       generation=2, enabled=True, expires_at=now+timedelta(days=1), fid='private-fid')
        for changes, allowed in [({}, True), ({'user_uid': 'other'}, False),
                                 ({'generation': 3}, False), ({'expires_at': now-timedelta(days=1)}, False)]:
            database = MagicMock()
            ref = database.collection.return_value.document.return_value.get.return_value
            ref.exists = True
            ref.to_dict.return_value = dict(current, **changes)
            with patch.object(push, 'connect'), patch.object(push, '_user_id', return_value='mysql'), \
                 patch.object(push, 'db', return_value=database), patch.object(push, 'send_message') as send:
                if allowed:
                    self.assertTrue(push.test_push(self.payload(), {'uid': 'uid'})['sent'])
                    send.assert_called_once()
                else:
                    with self.assertRaises(HTTPException) as caught:
                        push.test_push(self.payload(), {'uid': 'uid'})
                    self.assertEqual(caught.exception.status_code, 403)
                    send.assert_not_called()


if __name__ == '__main__':
    unittest.main()
