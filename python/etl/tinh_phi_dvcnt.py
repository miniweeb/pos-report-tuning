"""BAN MOI"""
import logging
import sys
import time
from datetime import date
from pathlib import Path

from db import get_conn, load_sql

log = logging.getLogger("tinh_phi_dvcnt")
SQL_FILE = Path(__file__).resolve().parents[2] / "sql/04_merge/merge_merchant_fee.sql"


def run(bc_dt: date) -> int:
    sql = load_sql(str(SQL_FILE))
    t0 = time.time()
    with get_conn() as conn, conn.cursor() as cur:
        cur.execute(sql, bc_dt=bc_dt)
        n = cur.rowcount
        conn.commit()
    log.info("Merged %s rows in %.1fs", n, time.time() - t0)
    return n


if __name__ == "__main__":
    logging.basicConfig(level=logging.INFO, format="[%(asctime)s] %(levelname)s %(name)s: %(message)s")
    run(date.fromisoformat(sys.argv[1]))