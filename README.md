# pos-report-tuning

Toi uu truy van bao cao tuan giao dich the POS va chuyen buoc tinh phi tu vong lap Python sang set-based.
Schema that da duoc che, moi file SQL dung bien `&&SCHEMA` (Toad / SQL*Plus se hoi gia tri khi chay).

## Cau truc

```
sql/
  00_baseline/v0_rpt_pos_weekly.sql   # ban goc chay cham (Dau vao 1.1)
  01_explain/get_plan.sql             # lay plan thuc te ALLSTATS LAST (Task 1)
  02_rewrite/v1_rpt_pos_weekly.sql    # ban toi uu (Task 3)
  03_ddl/ix_and_stats.sql             # index + virtual column + stats (Task 3)
  04_merge/merge_merchant_fee.sql     # MERGE set-based (Task 4)
  05_reconcile/reconcile.sql          # doi chieu V0 vs V1 (Task 5)
python/
  etl/db.py                           # ket noi + doc file .sql
  etl/tinh_phi_dvcnt_loop.py          # ban cu (Dau vao 1.2)
  etl/tinh_phi_dvcnt.py               # (Task 4)
  requirements.txt
docs/
  plans/plan_v0.png, plan_v1.png      # execution plan (Task 1, 3)
  benchmark.md                        # so sanh hieu nang (Task 6)
```