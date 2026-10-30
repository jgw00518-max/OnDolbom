import unittest
from unittest.mock import MagicMock, AsyncMock, patch
from fastapi import HTTPException
from pymysql import OperationalError
from python.features.family_room import membership
from python.features.chats.connection_manager import ConnectionManager


class MembershipTests(unittest.TestCase):
    def fixture(self, guardian=False, target=None, schedules=None, latest=None):
        connection = MagicMock()
        cursor = connection.cursor.return_value.__enter__.return_value
        actor = dict(participate_seq=1,user_id='actor',is_representative=int(guardian))
        rows = [dict(family_room_id='room'),actor]
        if target is not None: rows.append(target)
        if schedules: rows.append(latest)
        cursor.fetchone.side_effect = rows
        cursor.fetchall.return_value = schedules or []
        cursor.rowcount = 1
        return connection, cursor

    def test_leave_preserves_records_and_updates_only_membership(self):
        connection, cursor = self.fixture()
        with patch.object(membership,'connect',return_value=connection):
            result=membership.end_membership('room','actor')
        self.assertEqual(result['user_id'],'actor')
        self.assertEqual(result['released_schedules'],0)
        connection.commit.assert_called_once()
        sql=' '.join(call.args[0] for call in cursor.execute.call_args_list)
        self.assertNotIn('DELETE FROM',sql)
        self.assertIn('UPDATE participate SET left_at=CURRENT_TIMESTAMP',sql)
        self.assertNotIn('SET is_active',sql)
        self.assertIn("schedule_state='미완료' AND deleted_at IS NULL",sql)
        connection.close.assert_called_once()

    def test_generated_active_column_is_never_written(self):
        # 실제 스키마처럼 생성 컬럼에 쓰면 실패하도록 만들어 회귀를 검출한다.
        for guardian, seq in [(False,None),(True,2)]:
            target=dict(participate_seq=2,user_id='target',is_representative=0) if guardian else None
            connection,cursor=self.fixture(guardian=guardian,target=target)
            def execute(sql,params):
                if 'UPDATE participate' in sql and 'SET is_active' in sql:
                    raise OperationalError(3105,'generated column')
            cursor.execute.side_effect=execute
            with patch.object(membership,'connect',return_value=connection):
                result=membership.end_membership('room','actor',seq)
            self.assertEqual(result['result'],'OK')
            connection.commit.assert_called_once()

    def test_guardian_cannot_leave_and_non_guardian_cannot_kick(self):
        for guardian,target_seq in [(True,None),(False,2)]:
            connection,_=self.fixture(guardian=guardian)
            with patch.object(membership,'connect',return_value=connection):
                with self.assertRaises(HTTPException) as error:
                    membership.end_membership('room','actor',target_seq)
            self.assertEqual(error.exception.status_code,409 if guardian else 403)
            connection.rollback.assert_called_once()
            connection.commit.assert_not_called()

    def test_guardian_kicks_only_active_non_guardian_in_same_space(self):
        target=dict(participate_seq=2,user_id='target',is_representative=0)
        connection,cursor=self.fixture(guardian=True,target=target)
        with patch.object(membership,'connect',return_value=connection):
            result=membership.end_membership('room','actor',2)
        self.assertEqual(result['user_id'],'target')
        self.assertEqual(cursor.execute.call_args.args[1],(2,'room'))
        sql=' '.join(call.args[0] for call in cursor.execute.call_args_list)
        self.assertIn('participate_seq=%s AND family_room_id=%s',sql)

    def test_no_self_or_guardian_kick(self):
        for target in [dict(participate_seq=2,user_id='actor',is_representative=0),
                       dict(participate_seq=2,user_id='owner',is_representative=1)]:
            connection,_=self.fixture(guardian=True,target=target)
            with patch.object(membership,'connect',return_value=connection):
                with self.assertRaises(HTTPException) as error:
                    membership.end_membership('room','actor',2)
            self.assertEqual(error.exception.status_code,409)
            connection.commit.assert_not_called()

    def test_missing_space_actor_or_ended_target_cannot_change_data(self):
        for rows,expected in [([None],404),([{'family_room_id':'room'},None],403),
            ([{'family_room_id':'room'},{'user_id':'actor','is_representative':1},None],409)]:
            connection=MagicMock()
            connection.cursor.return_value.__enter__.return_value.fetchone.side_effect=rows
            with patch.object(membership,'connect',return_value=connection):
                with self.assertRaises(HTTPException) as error:
                    membership.end_membership('room','actor',2)
            self.assertEqual(error.exception.status_code,expected)
            connection.commit.assert_not_called()

    def test_release_keeps_latest_schedule_content_and_ends_pending_reconfirm(self):
        original=dict(schedule_seq=7,schedule_date='old',schedule_name='old',start_time='09:00',end_time='10:00',schedule_memo=None)
        latest=dict(schedule_date='new',schedule_name='changed',start_time='11:00',end_time='12:00',schedule_memo='memo')
        connection,cursor=self.fixture(schedules=[original],latest=latest)
        with patch.object(membership,'connect',return_value=connection):
            result=membership.end_membership('room','actor')
        self.assertEqual(result['released_schedules'],1)
        insert=next(call for call in cursor.execute.call_args_list if 'INSERT INTO update_schedule' in call.args[0])
        self.assertEqual(insert.args[1],(7,'new','room','actor','changed','11:00','12:00','memo'))
        self.assertIn('NULL,NULL',insert.args[0])
        update=next(call for call in cursor.execute.call_args_list if 'UPDATE create_schedule' in call.args[0])
        self.assertIn('accepted_by=NULL,accepted_at=NULL',update.args[0])
        connection.commit.assert_called_once()

    def test_failure_rolls_back_membership_and_schedule_together(self):
        connection,cursor=self.fixture()
        def execute(sql,args):
            if 'UPDATE participate' in sql: raise OperationalError('failed')
        cursor.execute.side_effect=execute
        with patch.object(membership,'connect',return_value=connection):
            with self.assertRaises(HTTPException) as error:
                membership.end_membership('room','actor')
        self.assertEqual(error.exception.status_code,503)
        connection.rollback.assert_called_once()
        connection.commit.assert_not_called()


class ChatExitTests(unittest.IsolatedAsyncioTestCase):
    async def test_only_target_connections_in_selected_room_close(self):
        manager=ConnectionManager()
        target=MagicMock(user_id='target',close=AsyncMock())
        other=MagicMock(user_id='other',close=AsyncMock())
        elsewhere=MagicMock(user_id='target',close=AsyncMock())
        manager.add('room',target);manager.add('room',other);manager.add('other-room',elsewhere)
        await manager.close_member('room','target')
        target.close.assert_awaited_once_with(4403)
        other.close.assert_not_called();elsewhere.close.assert_not_called()
        self.assertEqual(manager.rooms['room'],{other})
        self.assertEqual(manager.rooms['other-room'],{elsewhere})

class MembershipRouteTests(unittest.IsolatedAsyncioTestCase):
    async def test_socket_closes_only_after_successful_database_result(self):
        from python.features.family_room import router
        result=dict(result='OK',family_room_id='room',user_id='target')
        with patch.object(router,'run_in_threadpool',new=AsyncMock(return_value=result)) as execute, \
             patch.object(router.chat_manager,'close_member',new=AsyncMock()) as close:
            self.assertEqual(await router.remove_family_member('room',2,'guardian'),result)
            execute.assert_awaited_once_with(router.end_membership,'room','guardian',2)
            close.assert_awaited_once_with('room','target')
        with patch.object(router,'run_in_threadpool',new=AsyncMock(side_effect=HTTPException(403,'denied'))), \
             patch.object(router.chat_manager,'close_member',new=AsyncMock()) as close:
            with self.assertRaises(HTTPException):
                await router.leave_family_room('room','actor')
            close.assert_not_called()

if __name__=='__main__':unittest.main()
