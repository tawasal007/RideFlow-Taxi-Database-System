import os
from pathlib import Path
from dotenv import load_dotenv


load_dotenv()
BASE_DIR = Path(__file__).resolve().parent


def resolve_optional_path(value):
    if not value:
        return None
    path = Path(value)
    if not path.is_absolute():
        path = (BASE_DIR / path).resolve()
    return str(path)


class Config:
    SECRET_KEY = os.getenv("SECRET_KEY", "rideflow-dev-secret")
    MYSQL_HOST = os.getenv("MYSQL_HOST", "127.0.0.1")
    MYSQL_PORT = int(os.getenv("MYSQL_PORT", "3306"))
    MYSQL_USER = os.getenv("MYSQL_USER", "root")
    MYSQL_PASSWORD = os.getenv("MYSQL_PASSWORD", "")
    MYSQL_DATABASE = os.getenv("MYSQL_DATABASE", "rideflow")
    MYSQL_SSL_DISABLED = os.getenv("MYSQL_SSL_DISABLED", "true").lower() == "true"
    MYSQL_SSL_CA = resolve_optional_path(os.getenv("MYSQL_SSL_CA"))
