import asyncio
import os
import subprocess
import unittest
from unittest.mock import MagicMock, patch
from fastapi import FastAPI
from fastapi.testclient import TestClient
from python.features.schedules import reminder_lifecycle as lifecycle


class ReminderLifecycleTests(unittest.TestCase):
    def test_server_start_and_stop_manage_worker_without_blocking_health(self):
        process = MagicMock()
        app = FastAPI(lifespan=lifecycle.reminder_lifespan)
        @app.get('/health')
        def health():
            return {'status': 'ok'}
        with patch.dict(os.environ, {'ONDOLBOM_REMINDER_WORKER': '1'}), \
             patch.object(lifecycle, 'start_worker', return_value=process) as start, \
             patch.object(lifecycle, 'stop_worker') as stop:
            with TestClient(app) as client:
                start.assert_called_once()
                self.assertEqual(client.get('/health').json(), {'status': 'ok'})
                stop.assert_not_called()
            stop.assert_called_once_with(process)

    def test_default_api_start_does_not_spawn_worker(self):
        # 이전 터미널의 설정과 무관하게 환경 변수가 없는 기본 실행을 검사한다.
        with patch.dict(os.environ), patch.object(lifecycle, 'start_worker') as start:
            os.environ.pop('ONDOLBOM_REMINDER_WORKER', None)
            with TestClient(FastAPI(lifespan=lifecycle.reminder_lifespan)):
                start.assert_not_called()

    def test_test_environment_can_disable_real_notifications(self):
        with patch.dict(os.environ, {'ONDOLBOM_REMINDER_WORKER': '0'}), \
             patch.object(lifecycle, 'start_worker') as start:
            with TestClient(FastAPI(lifespan=lifecycle.reminder_lifespan)):
                start.assert_not_called()

    def test_worker_uses_same_python_and_explicit_project_root(self):
        with patch.object(lifecycle.subprocess, 'Popen') as spawn:
            lifecycle.start_worker()
        args, kwargs = spawn.call_args
        self.assertEqual(args[0], [lifecycle.sys.executable, '-m', 'python.features.schedules.reminder_worker'])
        self.assertEqual(kwargs['cwd'], lifecycle.ROOT)
        self.assertNotIn('shell', kwargs)

    def test_shutdown_terminates_and_reaps_or_kills_stalled_worker(self):
        for stalled in [False, True]:
            process = MagicMock()
            process.poll.return_value = None
            if stalled:
                process.wait.side_effect = [subprocess.TimeoutExpired('worker', 5), 0]
            lifecycle.stop_worker(process)
            process.terminate.assert_called_once()
            self.assertEqual(process.kill.call_count, int(stalled))
            process.wait.assert_any_call(timeout=5)


class ReminderSupervisorTests(unittest.IsolatedAsyncioTestCase):
    async def test_exited_worker_is_restarted_and_replacement_is_stopped(self):
        first, second = MagicMock(), MagicMock()
        first.poll.return_value = 1
        second.poll.return_value = None
        checked = asyncio.Event()
        release = asyncio.Event()
        calls = 0
        async def tick(_):
            nonlocal calls
            calls += 1
            if calls > 1:
                checked.set()
                await release.wait()
        with patch.dict(os.environ, {'ONDOLBOM_REMINDER_WORKER': '1'}), \
             patch.object(lifecycle, 'start_worker', side_effect=[first, second]) as start, \
             patch.object(lifecycle, 'stop_worker') as stop, \
             patch.object(lifecycle.asyncio, 'sleep', side_effect=tick):
            async with lifecycle.reminder_lifespan(None):
                await asyncio.wait_for(checked.wait(), timeout=2)
                self.assertEqual(start.call_count, 2)
            stop.assert_called_once_with(second)
