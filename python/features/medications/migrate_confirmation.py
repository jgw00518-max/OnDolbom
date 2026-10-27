"""python -m python.features.medications.migrate_confirmation 로 명시적으로 적용."""
from pathlib import Path

from python.database import connect


def main():
    connection = connect()
    try:
        with connection.cursor() as cursor:
            cursor.execute("""SELECT COLUMN_NAME FROM information_schema.COLUMNS
                WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'medication_log'
                  AND COLUMN_NAME = 'confirmed_by_user_id'""")
            if cursor.fetchone() is None:
                cursor.execute(Path(__file__).with_name("schema.sql").read_text(encoding="utf-8"))
        connection.commit()
    finally:
        connection.close()
    print("medication confirmation schema ready")


if __name__ == "__main__":
    main()
