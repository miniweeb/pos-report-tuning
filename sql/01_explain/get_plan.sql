-- Lay plan thuc te
-- 1):
ALTER SESSION SET statistics_level = ALL;
-- 2) Lay sql_id vua chay
SELECT sql_id, child_number, plan_hash_value, ROUND(elapsed_time/1e6) ela_s,
       buffer_gets, disk_reads, rows_processed
FROM   gv$sql
WHERE  sql_text LIKE '%BAO CAO CHI TIET GD POS%' AND sql_text NOT LIKE '%gv$sql%'
ORDER BY last_active_time DESC FETCH FIRST 5 ROWS ONLY;
-- 3) In plan
SELECT * FROM TABLE(DBMS_XPLAN.DISPLAY_CURSOR('&sql_id', NULL, 'ALLSTATS LAST +PEEKED_BINDS'));