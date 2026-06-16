from pathlib import Path

import mysql.connector

from config import Config


ROOT = Path(__file__).resolve().parent
SQL_DIR = ROOT / "sql"


def run_script(cursor, path):
    content = path.read_text(encoding="utf-8")
    statements = [stmt.strip() for stmt in content.split("\n-- statement-break\n") if stmt.strip()]
    for statement in statements:
        cursor.execute(statement)


def build_bootstrap_config():
    settings = {
        "host": Config.MYSQL_HOST,
        "port": Config.MYSQL_PORT,
        "user": Config.MYSQL_USER,
        "password": Config.MYSQL_PASSWORD,
        "ssl_disabled": Config.MYSQL_SSL_DISABLED,
        "autocommit": True,
    }
    if not Config.MYSQL_SSL_DISABLED and Config.MYSQL_SSL_CA:
        settings["ssl_ca"] = Config.MYSQL_SSL_CA
        settings["ssl_verify_cert"] = True
    return settings


def main():
    bootstrap_conn = mysql.connector.connect(**build_bootstrap_config())
    cursor = bootstrap_conn.cursor()
    for filename in [
        "01_schema.sql",
        "02_views_procedures_triggers.sql",
        "03_seed.sql",
        "05_dcl.sql",
    ]:
        run_script(cursor, SQL_DIR / filename)
        print(f"Applied {filename}")
    cursor.close()
    bootstrap_conn.close()


if __name__ == "__main__":
    main()
