"""가입용 코드가 확인되기 전에는 계정이 만들어지지 않는지 검증한다."""
import unittest
from unittest.mock import patch

from python.features.auth import password_reset as codes, signup
from python.tests.features import test_password_reset as reset_tests


class SignupTests(unittest.TestCase):
    def setUp(self):
        reset_tests.PasswordResetTests.setUp(self)
        self.client.app.include_router(signup.router, prefix="/auth")
        codes.auth.get_user_by_email.side_effect = codes.auth.UserNotFoundError("missing")
        self.create = patch.object(signup.auth, "create_user").start()
        self.addCleanup(patch.stopall)

    def post(self, step, **values):
        return self.client.post("/auth/signup/" + step, json={"email": self.email, **values})

    request = reset_tests.PasswordResetTests.request

    def proof(self):
        request_id, code = self.request()
        self.create.assert_not_called()
        result = self.post("verify", request_id=request_id, code=code)
        self.assertEqual(result.status_code, 200, result.text)
        return {"request_id": request_id, "verification_token": result.json()["verification_token"]}

    def test_signup_creates_verified_email_only_once(self):
        proof = self.proof()
        self.send.assert_called_once()
        self.assertEqual(self.send.call_args.kwargs["purpose"], "signup")
        result = self.post("confirm", **proof, password="new-password")
        self.assertEqual(result.status_code, 200, result.text)
        self.create.assert_called_once_with(email=self.email, password="new-password", email_verified=True, app="app")
        self.assertEqual(self.post("confirm", **proof, password="new-password").status_code, 400)

    def test_invalid_email_code_and_expiry_never_create_account(self):
        self.assertEqual(self.post("confirm", request_id="fake", verification_token="fake", password="new-password").status_code, 400)
        request_id, code = self.request()
        wrong = "000000" if code != "000000" else "111111"
        for _ in range(5):
            self.assertEqual(self.post("verify", request_id=request_id, code=wrong).status_code, 400)
        self.assertEqual(self.post("verify", request_id=request_id, code=code).status_code, 400)
        self.clock.return_value += 601
        request_id, code = self.request()
        self.clock.return_value += 601
        self.assertEqual(self.post("verify", request_id=request_id, code=code).status_code, 400)
        self.create.assert_not_called()

    def test_resend_invalidates_old_proof_and_throttles(self):
        proof = self.proof()
        self.assertEqual(self.post("request").status_code, 429)
        self.clock.return_value += 61
        self.request()
        self.assertEqual(self.post("confirm", **proof, password="new-password").status_code, 400)

    def test_email_binding_and_token_expiry(self):
        proof = self.proof()
        original = self.email
        self.email = "other@example.com"
        self.assertEqual(self.post("confirm", **proof, password="new-password").status_code, 400)
        self.email = original
        self.clock.return_value += 301
        self.assertEqual(self.post("confirm", **proof, password="new-password").status_code, 400)
        self.create.assert_not_called()

    def test_existing_accounts_never_receive_signup_code(self):
        codes.auth.get_user_by_email.side_effect = None
        result = self.post("request")
        self.assertEqual(result.status_code, 200)
        self.send.assert_not_called()
        self.create.assert_not_called()

    def test_reset_proof_cannot_create_account_and_signup_cannot_reset(self):
        proof = self.proof()
        reset_payload = {"email": self.email, "request_id": proof["request_id"],
                         "reset_token": proof["verification_token"], "password": "new-password"}
        self.assertEqual(self.client.post("/auth/password-reset/confirm", json=reset_payload).status_code, 400)
        codes.auth.get_user_by_email.side_effect = None
        request = self.client.post("/auth/password-reset/request", json={"email": self.email}).json()
        code = self.send.call_args.args[2]
        verified = self.client.post("/auth/password-reset/verify", json={"email": self.email,
            "request_id": request["request_id"], "code": code}).json()
        self.assertEqual(self.post("confirm", request_id=request["request_id"],
            verification_token=verified["reset_token"], password="new-password").status_code, 400)
        self.create.assert_not_called()

    def test_duplicate_account_race_does_not_overwrite(self):
        proof = self.proof()
        self.create.side_effect = codes.auth.EmailAlreadyExistsError("exists", None, None)
        self.assertEqual(self.post("confirm", **proof, password="new-password").status_code, 409)
        self.update.assert_not_called()


if __name__ == "__main__":
    unittest.main()
