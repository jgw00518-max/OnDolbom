"""실제 .env와 DB를 사용하지 않는 서버·연결 설정 테스트."""

import unittest
from pathlib import Path
from unittest.mock import patch

from fastapi.testclient import TestClient

from python.database import connect
from python.main import app


class DatabaseTests(unittest.TestCase):
    def setUp(self):
        self.settings = {
            "MYSQL_HOST": "file-host", "MYSQL_USER": "test-user",
            "MYSQL_PASSWORD": "test-password", "MYSQL_DATABASE": "test-db",
        }

    def test_health_without_db_connection(self):
        with patch("python.database.pymysql.connect") as mysql, TestClient(app) as client:
            response = client.get("/health")
            self.assertEqual(response.status_code, 200)
            self.assertEqual(response.json(), {"status": "ok"})
            self.assertEqual(client.get("/missing").status_code, 404)
            mysql.assert_not_called()

    def test_env_location_and_environment_precedence(self):
        with patch("python.database.dotenv_values", return_value=self.settings) as read_env, patch.dict(
            "os.environ", {"MYSQL_HOST": "environment-host"}, clear=True
        ), patch("python.database.pymysql.connect") as mysql:
            self.assertIs(connect(), mysql.return_value)
            read_env.assert_called_once_with(Path(__file__).resolve().parents[1] / ".env")
            self.assertEqual(mysql.call_args.kwargs["host"], "environment-host")
            self.assertEqual(mysql.call_args.kwargs["port"], 3306)
            self.assertFalse(mysql.call_args.kwargs["autocommit"])

    def test_missing_configuration_does_not_connect(self):
        with patch("python.database.dotenv_values", return_value={}), patch.dict(
            "os.environ", {}, clear=True
        ), patch("python.database.pymysql.connect") as mysql:
            with self.assertRaises(ValueError):
                connect()
            mysql.assert_not_called()

    def test_invalid_port_does_not_connect(self):
        for port in ("invalid", "0", "65536"):
            with self.subTest(port=port), patch(
                "python.database.dotenv_values", return_value={**self.settings, "MYSQL_PORT": port}
            ), patch.dict("os.environ", {}, clear=True), patch("python.database.pymysql.connect") as mysql:
                with self.assertRaises(ValueError):
                    connect()
                mysql.assert_not_called()


if __name__ == "__main__":
    unittest.main()
