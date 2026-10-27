"""기능별 SQL은 각 기능에 두고 연결 생성만 공유한다."""

import os
from pathlib import Path

import pymysql
from dotenv import dotenv_values
from pymysql.connections import Connection

def connect() -> Connection:
    """.env보다 환경변수를 우선하며, 연결 종료·commit은 호출자가 담당한다."""
    # 터미널 실행 위치와 관계없이 python/.env를 읽으며, 환경변수를 우선한다.
    env_file = Path(__file__).resolve().parent / ".env"
    settings = {**dotenv_values(env_file), **os.environ}
    required = ("MYSQL_HOST", "MYSQL_USER", "MYSQL_PASSWORD", "MYSQL_DATABASE")
    if any(settings.get(name) in (None, "") for name in required):
        raise ValueError("MySQL 환경 설정을 확인해 주세요.")
    try:
        port = int(settings.get("MYSQL_PORT", "3306"))
    except (TypeError, ValueError):
        raise ValueError("MYSQL_PORT는 정수여야 합니다.") from None
    if not 1 <= port <= 65535:
        raise ValueError("MYSQL_PORT 범위를 확인해 주세요.")
    # DictCursor는 컬럼명으로 결과를 읽게 한다. commit은 호출한 업무 함수가 결정한다.
    return pymysql.connect(
        host=settings["MYSQL_HOST"],
        port=port,
        user=settings["MYSQL_USER"],
        password=settings["MYSQL_PASSWORD"],
        database=settings["MYSQL_DATABASE"],
        charset="utf8mb4",
        cursorclass=pymysql.cursors.DictCursor,
        autocommit=False,
        connect_timeout=5,
    )
