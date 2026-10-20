# pos-report-tuning

Tối ưu truy vấn báo cáo tuần giao dịch thẻ POS (Oracle 19c Exadata) và chuyển bước tính phí chiết khấu ĐVCNT từ vòng lặp Python sang xử lý tập hợp (set-based).

> Schema thật đã được che bằng biến `&&SCHEMA` (Toad / SQL*Plus hỏi giá trị khi chạy).

## Kết quả

| Chỉ số | Trước | Sau | Cải thiện |
|---|---|---|---|
| Thời gian truy vấn báo cáo | 41m 12s | 1m 55s | ↓ 95% |
| Buffer gets | 612.384.910 | 23.677.155 | ↓ 96% |
| Physical read | 175 GB | 17,7 GB | ↓ 90% |
| Partition `W4_DOC_FULL` đọc | 32/32 | 1/32 | pruning |
| Bước tính phí (Python) | 2h 05m | 48s | ↓ 99% |
| Round-trip DB từ Python | 115.240 | 1 | ↓ 99,99% |
| **Tổng luồng báo cáo tuần** | **2h 52m** | **4m 10s** | **đạt SLA 30 phút** |

Kết quả V0 và V1 khớp 100% (số dòng, tổng tiền, tổng phí, `MINUS` hai chiều = 0).

## Bối cảnh

- Job `RPT_POS_WEEKLY` chạy 02:00 mỗi thứ Hai, SLA 30 phút.
- Bước tính phí ĐVCNT viết bằng vòng lặp Python: N+1 query cho ~38.400 ĐVCNT, commit từng dòng.

**Yêu cầu của người hướng dẫn**

1. Phân tích execution plan của các truy vấn chạy chậm để xác định bước gây tốn chi phí nhất.
2. Viết lại phần xử lý đang dùng vòng lặp trong Python bằng truy vấn tập hợp (set-based).

## Task và file tương ứng

| STT | Task | File |
|---|---|---|
| 1 | Đo baseline V0, lấy plan thực tế | `sql/00_baseline/v0_rpt_pos_weekly.sql`, `sql/01_explain/get_plan.sql`, `docs/plans/plan_v0.txt` |
| 2 | Xác định bước tốn chi phí nhất | `docs/plans/plan_v0.txt` (bảng hotspot bên dưới) |
| 3 | Viết lại truy vấn (V1) | `sql/02_rewrite/v1_rpt_pos_weekly.sql`, `sql/03_ddl/ix_and_stats.sql`, `docs/plans/plan_v1.txt` |
| 4 | Thay vòng lặp Python bằng 1 câu MERGE | `python/etl/tinh_phi_dvcnt_loop.py` (cũ), `python/etl/tinh_phi_dvcnt.py` + `sql/04_merge/merge_merchant_fee.sql` (mới) |
| 5 | Đối chiếu kết quả trước/sau | `sql/05_reconcile/reconcile.sql` |
| 6 | So sánh hiệu năng, cập nhật flow pipeline | `docs/benchmark.md` |

## Cấu trúc thư mục

```
sql/
  00_baseline/v0_rpt_pos_weekly.sql   # V0 - bản đang chạy PROD (11 CTE)
  01_explain/get_plan.sql             # lấy plan thực tế ALLSTATS LAST
  02_rewrite/v1_rpt_pos_weekly.sql    # V1 - bản tối ưu (18 CTE)
  03_ddl/ix_and_stats.sql             # index + virtual column + stats
  04_merge/merge_merchant_fee.sql     # MERGE set-based tính phí ĐVCNT
  05_reconcile/reconcile.sql          # đối chiếu V0 vs V1, loop vs MERGE
python/
  etl/db.py                           # kết nối Oracle + đọc file .sql
  etl/tinh_phi_dvcnt_loop.py          # bản cũ (vòng lặp, N+1 query)
  etl/tinh_phi_dvcnt.py               # bản mới (1 câu MERGE)
  requirements.txt
docs/
  plans/plan_v0.txt, plan_v1.txt      # execution plan ALLSTATS LAST
  benchmark.md                        # so sánh hiệu năng
```

Thông tin kết nối lấy từ biến môi trường; `.env` và `*.ini` đã nằm trong `.gitignore`.

## Tài liệu tham khảo

- [Oracle 19c - SQL Tuning Guide](https://docs.oracle.com/en/database/oracle/oracle-database/19/tgsql/)
- [Oracle - DBMS_XPLAN](https://docs.oracle.com/en/database/oracle/oracle-database/19/arpls/DBMS_XPLAN.html)
- [Oracle - MERGE](https://docs.oracle.com/en/database/oracle/oracle-database/19/sqlrf/MERGE.html)