"""완료 기록만 본인 초대함에서 삭제하며 원본 초대는 유지한다."""
import unittest
from types import SimpleNamespace
from unittest.mock import MagicMock, patch
from python.features.invites import history


def row(identifier, status):
    return dict(invite_id=identifier, invite_at='2026-10-29 10:00:00', invite_status=status)


class InviteHistoryDeleteTests(unittest.TestCase):
    def test_only_terminal_states_are_written_and_original_sql_is_read_only(self):
        conn = MagicMock()
        cursor = conn.cursor.return_value.__enter__.return_value
        cursor.fetchall.return_value = [row(str(i), status) for i, status in enumerate(
            ['수락', '거절', '취소', '만료', '대기', '발송대기', '발송실패'])]
        db = MagicMock()
        with patch.object(history, 'get_firebase_app'), patch.object(history.firestore, 'client', return_value=db):
            count = history.delete_history(conn, dict(user_id='owner', user_email='Owner@Mail.com'),
                                           'received', [str(i) for i in range(7)])
        self.assertEqual(count, 4)
        self.assertEqual(db.batch.return_value.set.call_count, 4)
        db.batch.return_value.commit.assert_called_once()
        sql, values = cursor.execute.call_args.args
        self.assertTrue(sql.strip().startswith('SELECT'))
        self.assertIn('LOWER(TRIM(i.invite_email))=%s', sql)
        self.assertEqual(values[-1], 'owner@mail.com')

    def test_unowned_or_pending_records_do_not_write_receipts(self):
        conn = MagicMock()
        for rows in ([], [row('pending', '대기'), row('sending', '발송대기')]):
            conn.cursor.return_value.__enter__.return_value.fetchall.return_value = rows
            with patch.object(history.firestore, 'client') as client:
                self.assertEqual(history.delete_history(conn, {'user_id': 'owner'}, 'sent', ['foreign']), 0)
            client.assert_not_called()
        sql, values = conn.cursor.return_value.__enter__.return_value.execute.call_args.args
        self.assertIn('i.inviter_id=%s', sql)
        self.assertEqual(values, ('foreign', 'owner', 'owner'))

    def test_listing_hides_only_completed_items_and_keeps_pending(self):
        rows = [row('accepted', '수락'), row('pending', '대기')]
        db = MagicMock()
        refs = [SimpleNamespace(path='completed'), SimpleNamespace(path='pending')]
        db.get_all.return_value = [SimpleNamespace(exists=True, reference=ref) for ref in refs]
        with patch.object(history, 'get_firebase_app'), \
             patch.object(history.firestore, 'client', return_value=db), \
             patch.object(history, 'hidden_ref', side_effect=refs):
            self.assertEqual(history.visible_history(rows, 'owner', 'received'), [rows[1]])

    def test_owner_and_mailbox_have_separate_storage_paths(self):
        db = MagicMock()
        history.hidden_ref(db, 'owner-1', 'received', row('id', '만료'))
        first_owner = db.collection.return_value.document.call_args.args[0]
        first_key = db.collection.return_value.document.return_value.collection.return_value.document.call_args.args[0]
        history.hidden_ref(db, 'owner-2', 'sent', row('id', '만료'))
        second_owner = db.collection.return_value.document.call_args.args[0]
        second_key = db.collection.return_value.document.return_value.collection.return_value.document.call_args.args[0]
        self.assertNotEqual(first_owner, second_owner)
        self.assertNotEqual(first_key, second_key)
