"""실제 공유 DB를 수정하지 않고 주보호자 이전 권한·원자성·경합을 검증한다."""
from concurrent.futures import ThreadPoolExecutor
from copy import deepcopy
from threading import Lock
import unittest
from unittest.mock import MagicMock, patch

from fastapi import HTTPException
from fastapi.testclient import TestClient
from pymysql import OperationalError

from python.features.family_room import membership
from python.features.family_room import router
from python.main import app


def member(seq, user_id, representative=0):
    return dict(participate_seq=seq, user_id=user_id, is_representative=representative)


class RepresentativeTransferTests(unittest.TestCase):
    def fixture(self, members=None, users=None):
        connection = MagicMock()
        cursor = connection.cursor.return_value.__enter__.return_value
        cursor.fetchone.return_value = {'family_room_id': 'room'}
        cursor.fetchall.side_effect = [
            members if members is not None else [member(1, 'actor', 1), member(2, 'target')],
            users if users is not None else [
                dict(user_id='actor', withdrawn_at=None),
                dict(user_id='target', withdrawn_at=None),
            ],
        ]
        cursor.rowcount = 1
        return connection, cursor

    def test_success_changes_only_two_roles_and_locks_space_first(self):
        connection, cursor = self.fixture()
        with patch.object(membership, 'connect', return_value=connection):
            result = membership.transfer_representative('room', 'actor', 'target')
        self.assertEqual(result, dict(result='OK', family_room_id='room',
            previous_representative_user_id='actor', representative_user_id='target'))
        calls = cursor.execute.call_args_list
        self.assertIn('family_room_deleted_at IS NULL', calls[0].args[0])
        self.assertIn('FOR UPDATE', calls[0].args[0])
        self.assertIn('left_at IS NULL AND is_active=1', calls[1].args[0])
        self.assertIn('FOR UPDATE', calls[1].args[0])
        self.assertEqual(calls[2].args[1], ('actor', 'target'))
        self.assertIn('FOR UPDATE', calls[2].args[0])
        updates = [call for call in calls if call.args[0].startswith('UPDATE')]
        self.assertEqual(len(updates), 2)
        self.assertEqual(updates[0].args[1], (1, 'room', 'actor'))
        self.assertEqual(updates[1].args[1], (2, 'room', 'target'))
        for call in updates:
            # SET 대상은 역할뿐이다. 생성자·참여 상태·기존 기록을 수정하지 않는다.
            self.assertIn('UPDATE participate SET is_representative=', call.args[0])
            self.assertNotIn(',', call.args[0].split(' WHERE')[0])
        connection.commit.assert_called_once()
        connection.rollback.assert_not_called()
        connection.close.assert_called_once()

    def assert_rejected(self, connection, expected, target='target'):
        with patch.object(membership, 'connect', return_value=connection):
            with self.assertRaises(HTTPException) as error:
                membership.transfer_representative('room', 'actor', target)
        self.assertEqual(error.exception.status_code, expected)
        connection.commit.assert_not_called()
        connection.rollback.assert_called_once()
        connection.close.assert_called_once()

    def test_missing_or_deleted_room(self):
        connection, cursor = self.fixture()
        cursor.fetchone.return_value = None
        self.assert_rejected(connection, 404)

    def test_non_member_and_general_family_cannot_transfer(self):
        for members in [[], [member(1, 'actor'), member(2, 'target', 1)]]:
            with self.subTest(members=members):
                connection, _ = self.fixture(members=members)
                self.assert_rejected(connection, 403)

    def test_self_target_missing_target_and_invalid_roles_are_rejected(self):
        for members, target in [
            ([member(1, 'actor', 1)], 'actor'),
            ([member(1, 'actor', 1)], 'target'),
            ([member(1, 'actor', 1), member(2, 'target', 1)], 'target'),
            ([member(1, 'actor', 1), member(2, 'target', 2)], 'target'),
        ]:
            with self.subTest(target=target, members=members):
                connection, _ = self.fixture(members=members)
                self.assert_rejected(connection, 409, target)

    def test_withdrawn_or_missing_accounts_are_rejected_before_updates(self):
        for users, expected in [
            ([dict(user_id='actor', withdrawn_at='deleted'),
              dict(user_id='target', withdrawn_at=None)], 403),
            ([dict(user_id='actor', withdrawn_at=None),
              dict(user_id='target', withdrawn_at='deleted')], 409),
            ([dict(user_id='actor', withdrawn_at=None)], 409),
            ([dict(user_id='target', withdrawn_at=None)], 403),
        ]:
            with self.subTest(users=users):
                connection, cursor = self.fixture(users=users)
                self.assert_rejected(connection, expected)
                self.assertFalse(any(call.args[0].startswith('UPDATE')
                    for call in cursor.execute.call_args_list))

    def test_failure_after_demotion_or_on_commit_rolls_back_both_roles(self):
        for stage in ['demote', 'promote', 'commit']:
            with self.subTest(stage=stage):
                connection, cursor = self.fixture()
                failure = OperationalError(2006, 'private database details')
                def execute(sql, params):
                    if ((stage == 'demote' and sql.startswith('UPDATE participate SET is_representative=0'))
                            or (stage == 'promote' and sql.startswith('UPDATE participate SET is_representative=1'))):
                        raise failure
                cursor.execute.side_effect = execute
                if stage == 'commit':
                    connection.commit.side_effect = failure
                with patch.object(membership, 'connect', return_value=connection):
                    with self.assertRaises(HTTPException) as error:
                        membership.transfer_representative('room', 'actor', 'target')
                self.assertEqual(error.exception.status_code, 503)
                self.assertNotIn('private', error.exception.detail)
                connection.rollback.assert_called_once()
                connection.close.assert_called_once()
                if stage != 'commit':
                    connection.commit.assert_not_called()

    def test_conditional_update_mismatch_rolls_back(self):
        for failed_role in [0, 1]:
            with self.subTest(role=failed_role):
                connection, cursor = self.fixture()
                def execute(sql, params):
                    if sql.startswith(f'UPDATE participate SET is_representative={failed_role}'):
                        cursor.rowcount = 0
                cursor.execute.side_effect = execute
                self.assert_rejected(connection, 409)

    def test_connection_failure_is_sanitized(self):
        with patch.object(membership, 'connect', side_effect=ValueError('secret')):
            with self.assertRaises(HTTPException) as error:
                membership.transfer_representative('room', 'actor', 'target')
        self.assertEqual(error.exception.status_code, 503)
        self.assertNotIn('secret', error.exception.detail)


class RepresentativeTransferRouteTests(unittest.TestCase):
    def setUp(self):
        self.client = TestClient(app)
        app.dependency_overrides[router.get_current_user_id] = lambda: 'verified-actor'

    def tearDown(self):
        app.dependency_overrides.pop(router.get_current_user_id, None)
        self.client.close()

    def test_api_uses_authenticated_actor_and_keeps_chat_connections(self):
        result = dict(result='OK', family_room_id='room',
            previous_representative_user_id='verified-actor', representative_user_id='target')
        with patch.object(router, 'transfer_representative', return_value=result) as transfer, \
             patch.object(router.chat_manager, 'close_room') as close_room, \
             patch.object(router.chat_manager, 'close_member') as close_member:
            response = self.client.post('/family-room/room/transfer-representative',
                json={'target_user_id': 'target'})
        self.assertEqual(response.status_code, 200)
        self.assertEqual(response.json(), result)
        transfer.assert_called_once_with('room', 'verified-actor', 'target')
        close_room.assert_not_called()
        close_member.assert_not_called()

    def test_invalid_payload_and_forged_actor_never_reach_database(self):
        for payload in [None, {}, {'target_user_id': ''}, {'target_user_id': 'a b'},
                        {'target_user_id': 'a' * 51}, {'target_user_id': 2},
                        {'target_user_id': 'target', 'user_id': 'forged'},
                        {'target_user_id': 'target', 'is_representative': 1}]:
            with self.subTest(payload=payload), patch.object(router, 'transfer_representative') as transfer:
                response = self.client.post('/family-room/room/transfer-representative', json=payload)
                self.assertEqual(response.status_code, 422)
                transfer.assert_not_called()

    def test_unauthenticated_request_does_not_connect(self):
        app.dependency_overrides.pop(router.get_current_user_id)
        with patch.object(router, 'connect') as connect, \
             patch.object(router, 'transfer_representative') as transfer:
            response = self.client.post('/family-room/room/transfer-representative',
                json={'target_user_id': 'target'})
        self.assertEqual(response.status_code, 401)
        connect.assert_not_called()
        transfer.assert_not_called()

    def test_business_error_is_preserved(self):
        with patch.object(router, 'transfer_representative', side_effect=HTTPException(403, '권한 없음')):
            response = self.client.post('/family-room/room/transfer-representative',
                json={'target_user_id': 'target'})
        self.assertEqual(response.status_code, 403)
        self.assertEqual(response.json()['detail'], '권한 없음')


class ConcurrentTransferTests(unittest.TestCase):
    def test_two_transfers_from_same_representative_only_one_commits(self):
        # DB 대신 공간 잠금을 모사한다. 대기 요청은 앞선 commit 후 역할을 다시 읽어야 한다.
        lock = Lock()
        members = [member(1, 'actor', 1), member(2, 'a'), member(3, 'b')]

        class Connection:
            rowcount = 0
            def __init__(self):
                self.locked = False
                self.committed = False
            def cursor(self):
                return self
            def __enter__(self):
                return self
            def __exit__(self, *args):
                return False
            def execute(self, sql, params):
                if sql.startswith('SELECT family_room_id'):
                    if not lock.acquire(timeout=5):
                        raise TimeoutError('모의 공간 잠금 시간 초과')
                    self.locked = True
                    self.before = deepcopy(members)
                    self.rows = [{'family_room_id': 'room'}]
                elif sql.startswith('SELECT participate_seq'):
                    self.rows = deepcopy(members)
                elif sql.startswith('SELECT user_id'):
                    self.rows = [dict(user_id=user_id, withdrawn_at=None) for user_id in params]
                elif sql.startswith('UPDATE participate'):
                    role = 0 if sql.startswith('UPDATE participate SET is_representative=0') else 1
                    for row in members:
                        if row['participate_seq'] == params[0] and row['user_id'] == params[2]:
                            row['is_representative'] = role
                            self.rowcount = 1
            def fetchone(self):
                return self.rows[0]
            def fetchall(self):
                return self.rows
            def commit(self):
                self.committed = True
            def rollback(self):
                if self.locked and not self.committed:
                    members[:] = self.before
            def close(self):
                if self.locked:
                    lock.release()

        def attempt(target):
            try:
                return membership.transfer_representative('room', 'actor', target)
            except HTTPException as error:
                return error.status_code

        with patch.object(membership, 'connect', side_effect=Connection):
            with ThreadPoolExecutor(max_workers=2) as pool:
                results = list(pool.map(attempt, ['a', 'b']))
        self.assertEqual(sum(isinstance(result, dict) for result in results), 1)
        self.assertIn(403, results)
        representatives = [row for row in members if row['is_representative'] == 1]
        self.assertEqual(len(representatives), 1)
        self.assertIn(representatives[0]['user_id'], ['a', 'b'])


if __name__ == '__main__':
    unittest.main()
