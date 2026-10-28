"""명시적으로 요청한 경우에만 API에 worker를 연결한다. 기본은 분리 실행이다."""
import asyncio
from contextlib import asynccontextmanager, suppress
import logging
import os
from pathlib import Path
import subprocess
import sys

logger = logging.getLogger(__name__)
ROOT = Path(__file__).resolve().parents[3]


def start_worker():
    # 별도 프로세스에서 동기 MySQL·Firestore를 처리해 앱 요청을 막지 않는다.
    # shell을 사용하지 않고 API와 같은 Python 환경·프로젝트 경로를 사용한다.
    try:
        return subprocess.Popen(
            [sys.executable, '-m', 'python.features.schedules.reminder_worker'],
            cwd=ROOT,
            creationflags=subprocess.CREATE_NO_WINDOW if os.name == 'nt' else 0,
        )
    except OSError:
        logger.exception('재알림 worker 시작 실패; 5초 후 재시도')
        return None


def stop_worker(process):
    if process is None:
        return
    if process.poll() is None:
        # worker의 현재 검사도 종료한다. DB 연결 잠금은 프로세스 종료로 해제된다.
        process.terminate()
    try:
        process.wait(timeout=5)
    except subprocess.TimeoutExpired:
        process.kill()
        process.wait()


@asynccontextmanager
async def reminder_lifespan(app):
    # 팀원 API를 켤 때 공유 Firestore를 조회하는 worker가 중복 실행되지 않게 기본 비활성화한다.
    # 기존 통합 실행이 필요할 때만 환경 변수로 명시적으로 활성화한다.
    if os.getenv('ONDOLBOM_REMINDER_WORKER', '0').lower() not in {'1', 'true', 'on'}:
        yield
        return
    process = start_worker()

    async def supervise():
        nonlocal process
        while True:
            await asyncio.sleep(5)
            if process is None or process.poll() is not None:
                if process is not None:
                    # 종료된 자식을 회수하고 새 worker를 시작한다.
                    process.wait()
                logger.warning('재알림 worker가 종료되어 다시 시작합니다.')
                process = start_worker()

    monitor = asyncio.create_task(supervise())
    try:
        yield
    finally:
        monitor.cancel()
        with suppress(asyncio.CancelledError):
            await monitor
        # 서버 종료·--reload 시 자식도 종료해 이전 worker를 남기지 않는다.
        await asyncio.to_thread(stop_worker, process)
