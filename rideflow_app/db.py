from contextlib import contextmanager

import mysql.connector
from flask import current_app, g
from mysql.connector import pooling


def build_mysql_config(config):
    settings = {
        "host": config["MYSQL_HOST"],
        "port": config["MYSQL_PORT"],
        "user": config["MYSQL_USER"],
        "password": config["MYSQL_PASSWORD"],
        "database": config["MYSQL_DATABASE"],
        "ssl_disabled": config["MYSQL_SSL_DISABLED"],
        "autocommit": False,
    }
    if not config["MYSQL_SSL_DISABLED"] and config.get("MYSQL_SSL_CA"):
        settings["ssl_ca"] = config["MYSQL_SSL_CA"]
        settings["ssl_verify_cert"] = True
    return settings


def get_pool():
    pool = current_app.extensions.get("mysql_pool")
    if pool is None:
        config = current_app.config
        pool = pooling.MySQLConnectionPool(
            pool_name="rideflow_pool",
            pool_size=8,
            **build_mysql_config(config),
        )
        current_app.extensions["mysql_pool"] = pool
    return pool


@contextmanager
def get_conn():
    conn = get_pool().get_connection()
    try:
        yield conn
        conn.commit()
    except Exception:
        conn.rollback()
        raise
    finally:
        conn.close()


def fetch_all(query, params=None):
    with get_conn() as conn:
        cursor = conn.cursor(dictionary=True)
        cursor.execute(query, params or ())
        rows = cursor.fetchall()
        cursor.close()
        return rows


def fetch_one(query, params=None):
    with get_conn() as conn:
        cursor = conn.cursor(dictionary=True)
        cursor.execute(query, params or ())
        row = cursor.fetchone()
        cursor.close()
        return row


def execute(query, params=None):
    with get_conn() as conn:
        cursor = conn.cursor(dictionary=True)
        cursor.execute(query, params or ())
        lastrowid = cursor.lastrowid
        cursor.close()
        return lastrowid


def execute_many(statements):
    with get_conn() as conn:
        cursor = conn.cursor()
        for query, params in statements:
            cursor.execute(query, params or ())
        cursor.close()
