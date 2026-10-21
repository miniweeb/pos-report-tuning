"""Ket noi Oracle. Thong tin lay tu bien moi truong"""
import os
import oracledb

SCHEMA = os.environ["DWH_SCHEMA"]          # da che trong tai lieu


def get_conn():
    return oracledb.connect(user=os.environ["DWH_USER"],
                            password=os.environ["DWH_PWD"],
                            dsn=os.environ["DWH_DSN"])


def load_sql(path: str) -> str:
    """Doc file .sql, thay bien &&SCHEMA. va bo dau ; cuoi."""
    with open(path, encoding="utf-8") as f:
        sql = f.read().replace("&&SCHEMA..", f"{SCHEMA}.")
    return sql.strip().rstrip(";")