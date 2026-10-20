"""BAN CU."""
from db import get_conn, SCHEMA


def run(bc_dt):
    conn = get_conn()
    cur = conn.cursor()
    cur.execute(f"SELECT DISTINCT MID FROM {SCHEMA}.STG_W4_POS_TXN_WEEKLY")
    for (mid,) in cur.fetchall():                       # ~38.400 DVCNT
        cur.execute(f"SELECT GD_AMT, GD_TYPE FROM {SCHEMA}.STG_W4_POS_TXN_WEEKLY "
                    "WHERE MID = :1", [mid])
        tot = sum(-amt if typ == "R" else amt for amt, typ in cur.fetchall())
        cur.execute(f"SELECT FEE_RATE FROM {SCHEMA}.W4_MERCHANT_FEE_TARIFF "
                    "WHERE MID = :1 AND :2 BETWEEN EFF_FROM AND EFF_TO", [mid, bc_dt])
        rate = (cur.fetchone() or [0.011])[0]
        fee = round(tot * rate)
        cur.execute(f"INSERT INTO {SCHEMA}.RPT_FEE_LOOP VALUES (:1,:2,:3,:4,:5)",
                    [bc_dt, mid, tot, fee, round(fee * 0.1)])
        conn.commit()