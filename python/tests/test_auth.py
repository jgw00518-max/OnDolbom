import unittest

from fastapi import HTTPException
from starlette.requests import Request

from python.auth import get_current_user_id


class AuthTests(unittest.TestCase):
    def test_validated_server_state_supplies_user_id(self):
        request = Request({"type": "http", "state": {"user_id": "verified-user"}})
        self.assertEqual(get_current_user_id(request), "verified-user")

    def test_invalid_or_missing_state_is_rejected(self):
        for user_id in (None, "", "  ", 123, "x" * 51):
            with self.subTest(user_id=user_id):
                request = Request({"type": "http", "state": {"user_id": user_id}})
                with self.assertRaises(HTTPException) as caught:
                    get_current_user_id(request)
                self.assertEqual(caught.exception.status_code, 401)


if __name__ == "__main__":
    unittest.main()
