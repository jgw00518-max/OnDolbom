"""실제 메일·Firebase 비밀번호를 바꾸지 않고 재설정 상태 전이를 검증한다."""
import copy
import unittest
from types import SimpleNamespace
from unittest.mock import patch

from fastapi import FastAPI
from fastapi.testclient import TestClient
from python.features.auth import password_reset as reset


class Document:
    def __init__(self):
        self.row = None

    def get(self, **kwargs):
        return SimpleNamespace(to_dict=lambda: copy.deepcopy(self.row))


class Transaction:
    def set(self, doc, row):
        doc.row = copy.deepcopy(row)

    def update(self, doc, values):
        doc.row.update(values)


class PasswordResetTests(unittest.TestCase):
    def setUp(self):
        self.docs = {}
        self.db = SimpleNamespace(collection=lambda name: SimpleNamespace(
            document=lambda key: self.docs.setdefault((name, key), Document())))
        self.config = {"PASSWORD_RESET_SECRET": "s" * 48}
        self.user = SimpleNamespace(uid="family-uid", disabled=False,
                                    provider_data=[SimpleNamespace(provider_id="password")])
        self.patches = [
            patch.object(reset, "settings", return_value=self.config),
            patch.object(reset, "get_firebase_app", return_value="app"),
            patch.object(reset.firestore, "client", return_value=self.db),
            patch.object(reset, "run_transaction", side_effect=lambda db, op: op(Transaction())),
            patch.object(reset.auth, "get_user_by_email", return_value=self.user),
            patch.object(reset, "send_code"),
            patch.object(reset.auth, "update_user"),
            patch.object(reset.auth, "revoke_refresh_tokens"),
            patch.object(reset.time, "time", return_value=1000000),
        ]
        mocks = [p.start() for p in self.patches]
        self.send, self.update, self.revoke, self.clock = mocks[5:]
        for p in self.patches:
            self.addCleanup(p.stop)
        app = FastAPI()
        app.include_router(reset.router, prefix="/auth")
        self.client = TestClient(app)
        self.email = "family@example.com"

    def post(self, step, **values):
        return self.client.post("/auth/password-reset/" + step, json={"email": self.email, **values})

    def request(self):
        result = self.post("request")
        self.assertEqual(result.status_code, 200, result.text)
        return result.json()["request_id"], self.send.call_args.args[2]

    def proof(self):
        request_id, code = self.request()
        result = self.post("verify", request_id=request_id, code=code)
        self.assertEqual(result.status_code, 200, result.text)
        return {"request_id": request_id, "reset_token": result.json()["reset_token"]}

    def test_full_flow_and_single_use(self):
        proof = self.proof()
        result = self.post("confirm", **proof, password="new-password")
        self.assertEqual(result.status_code, 200)
        self.assertEqual(result.headers["cache-control"], "no-store")
        self.update.assert_called_once_with("family-uid", password="new-password", app="app")
        self.revoke.assert_called_once()
        self.assertEqual(self.post("confirm", **proof, password="another-password").status_code, 400)

    def test_five_wrong_attempts_lock_even_correct_code(self):
        request_id, code = self.request()
        wrong = "000000" if code != "000000" else "111111"
        for _ in range(5):
            self.assertEqual(self.post("verify", request_id=request_id, code=wrong).status_code, 400)
        self.assertEqual(self.post("verify", request_id=request_id, code=code).status_code, 400)
        self.update.assert_not_called()

    def test_expiry_resend_and_code_replay(self):
        request_id, code = self.request()
        self.assertEqual(self.post("request").status_code, 429)
        self.clock.return_value += 601
        self.assertEqual(self.post("verify", request_id=request_id, code=code).status_code, 400)
        new_id, new_code = self.request()
        self.assertEqual(self.post("verify", request_id=request_id, code=code).status_code, 400)
        self.assertEqual(self.post("verify", request_id=new_id, code=new_code).status_code, 200)
        self.assertEqual(self.post("verify", request_id=new_id, code=new_code).status_code, 400)

    def test_unknown_social_disabled_never_receive_mail(self):
        for index, kind in enumerate(("missing", "social", "disabled")):
            self.email = f"{kind}@example.com"
            with patch.object(reset.auth, "get_user_by_email") as lookup:
                if kind == "missing":
                    lookup.side_effect = reset.auth.UserNotFoundError("missing")
                else:
                    lookup.return_value = SimpleNamespace(uid="other", disabled=kind == "disabled",
                        provider_data=[SimpleNamespace(provider_id="google.com")])
                result = self.post("request")
            self.assertEqual(result.status_code, 200)
        self.send.assert_not_called()

    def test_wrong_token_and_expired_token(self):
        proof = self.proof()
        wrong = {**proof, "reset_token": "incorrect"}
        self.assertEqual(self.post("confirm", **wrong, password="new-password").status_code, 400)
        self.clock.return_value += 301
        self.assertEqual(self.post("confirm", **proof, password="new-password").status_code, 400)
        self.update.assert_not_called()

    def test_provider_change_and_firebase_failure_fail_closed(self):
        proof = self.proof()
        self.update.side_effect = RuntimeError("private details")
        result = self.post("confirm", **proof, password="new-password")
        self.assertEqual(result.status_code, 503)
        self.assertNotIn("private details", result.text)
        self.assertEqual(self.post("confirm", **proof, password="new-password").status_code, 400)

    def test_validation_before_consumption(self):
        proof = self.proof()
        self.assertEqual(self.post("confirm", **proof, password="123").status_code, 422)
        self.assertEqual(self.post("confirm", **proof, password="new-password").status_code, 200)

    def test_user_disabled_after_proof_cannot_reset(self):
        proof = self.proof()
        self.user.disabled = True
        self.assertEqual(self.post("confirm", **proof, password="new-password").status_code, 400)
        self.update.assert_not_called()

    def test_smtp_failure_does_not_activate_code(self):
        self.send.side_effect = RuntimeError("private smtp password")
        result = self.post("request")
        self.assertEqual(result.status_code, 503)
        self.assertNotIn("private smtp password", result.text)
        row = next(doc.row for (collection, _), doc in self.docs.items()
                   if collection == "password_reset_challenges")
        self.assertEqual(row["phase"], "sending")
        code = self.send.call_args.args[2]
        self.assertEqual(self.post("verify", request_id=row["request_id"], code=code).status_code, 400)

    def test_hourly_email_limit(self):
        for _ in range(5):
            self.request()
            self.clock.return_value += 61
        self.assertEqual(self.post("request").status_code, 429)


if __name__ == "__main__":
    unittest.main()
