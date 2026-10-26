"""프로젝트 루트에서 python -m python.features.memos.migrate_likes 로 명시적으로 적용."""
from pathlib import Path

from python.database import connect


def main():
    sql = Path(__file__).with_name("schema.sql").read_text(encoding="utf-8")
    connection = connect()
    try:
        with connection.cursor() as cursor:
            cursor.execute(sql)
        connection.commit()
    finally:
        connection.close()
    print("memo_like table ready")


if __name__ == "__main__":
    main()
