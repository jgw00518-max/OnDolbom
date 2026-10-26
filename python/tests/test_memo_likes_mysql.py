"""명시적 ONDOLBOM_MYSQL_TESTS=1 실행만 실제 DB의 임시 메모로 동시성을 검사한다.

기존 메모·좋아요는 변경하지 않으며 UUID로 만든 테스트 메모와 그 기록만 정리한다.
Firebase 인증 자체는 test_memo_likes.py에서 검증한다.
"""
from concurrent.futures import ThreadPoolExecutor
import os
import unittest
from uuid import uuid4

from fastapi import HTTPException
import pymysql

from python.database import connect
from python.features.memos.router import MemoLikeCreate, delete_memo, like_memo, select_memos


@unittest.skipUnless(os.environ.get("ONDOLBOM_MYSQL_TESTS") == "1", "explicit MySQL test opt-in required")
class MemoLikeMySQLTests(unittest.TestCase):
    def setUp(self):
        conn = connect()
        try:
            with conn.cursor() as cursor:
                cursor.execute("""SELECT p.family_room_id, p.user_id FROM participate AS p
                    JOIN family_room AS f ON f.family_room_id = p.family_room_id
                    JOIN `user` AS u ON u.user_id = p.user_id
                    WHERE p.is_active = 1 AND p.left_at IS NULL
                      AND f.family_room_deleted_at IS NULL AND u.withdrawn_at IS NULL LIMIT 1""")
                member = cursor.fetchone()
                if member is None:
                    self.skipTest("active room member required for temporary memo fixture")
                self.room_id, self.user_id = member["family_room_id"], member["user_id"]
                self.memo_id = "like-test-" + str(uuid4())
                self.key = (self.memo_id, self.room_id, self.user_id)
                cursor.execute("""INSERT INTO memo (memo_id, family_room_id, user_id, memo_content, likes)
                    VALUES (%s, %s, %s, %s, NULL)""", (*self.key, "Temporary like API integration test"))
            conn.commit()
        finally:
            conn.close()
        self.addCleanup(self.clean_fixture)

    def clean_fixture(self):
        conn = connect()
        try:
            with conn.cursor() as cursor:
                cursor.execute("DELETE FROM memo_like WHERE memo_id = %s AND family_room_id = %s AND memo_author_id = %s", self.key)
                cursor.execute("DELETE FROM memo WHERE memo_id = %s AND family_room_id = %s AND user_id = %s", self.key)
            conn.commit()
        finally:
            conn.close()

    def test_concurrent_retries_unique_constraint_and_deleted_memo(self):
        data = MemoLikeCreate(family_room_id=self.room_id, author_user_id=self.user_id)
        with ThreadPoolExecutor(max_workers=4) as pool:
            responses = list(pool.map(lambda _: like_memo(data, self.memo_id, self.user_id), range(8)))
        self.assertEqual(sum(not result["already_liked"] for result in responses), 1)
        self.assertTrue(all(result["likes"] == 1 and result["is_liked"] for result in responses))

        conn = connect()
        try:
            with conn.cursor() as cursor:
                cursor.execute("SELECT likes FROM memo WHERE memo_id = %s AND family_room_id = %s AND user_id = %s", self.key)
                self.assertEqual(cursor.fetchone()["likes"], 1)
                cursor.execute("SELECT COUNT(*) AS total FROM memo_like WHERE memo_id = %s AND family_room_id = %s AND memo_author_id = %s", self.key)
                self.assertEqual(cursor.fetchone()["total"], 1)
                with self.assertRaises(pymysql.IntegrityError) as duplicate:
                    cursor.execute("INSERT INTO memo_like (memo_id, family_room_id, memo_author_id, user_id) VALUES (%s, %s, %s, %s)", (*self.key, self.user_id))
                self.assertEqual(duplicate.exception.args[0], 1062)
            conn.rollback()
        finally:
            conn.close()

        result = select_memos(family_room_id=self.room_id, limit=100, offset=0, current_user_id=self.user_id)
        memo = next(item for item in result["results"] if item["memo_id"] == self.memo_id)
        self.assertEqual(memo["likes"], 1)
        self.assertEqual(memo["is_liked"], 1)
        delete_memo(self.memo_id, self.room_id, self.user_id)
        with self.assertRaises(HTTPException) as deleted:
            like_memo(data, self.memo_id, self.user_id)
        self.assertEqual(deleted.exception.status_code, 404)


if __name__ == "__main__":
    unittest.main()
