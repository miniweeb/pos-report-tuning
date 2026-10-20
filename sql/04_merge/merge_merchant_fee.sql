/* Tinh phi chiet khau DVCNT - set-based, thay vong lap Python */
MERGE INTO &&SCHEMA..RPT_MERCHANT_FEE_WEEKLY t
USING (
    WITH gd AS (
        SELECT g.MID
             , SUM(CASE WHEN g.GD_TYPE = 'R' THEN -g.GD_AMT ELSE g.GD_AMT END) AS TOT_AMT
        FROM   &&SCHEMA..STG_W4_POS_TXN_WEEKLY g
        GROUP BY g.MID
    ), bp AS (
        SELECT b.MID, MAX(b.FEE_RATE) AS FEE_RATE
        FROM   &&SCHEMA..W4_MERCHANT_FEE_TARIFF b
        WHERE  :bc_dt BETWEEN b.EFF_FROM AND b.EFF_TO
        GROUP BY b.MID
    )
    SELECT :bc_dt AS BC_DT, gd.MID, gd.TOT_AMT
         , ROUND(gd.TOT_AMT * NVL(bp.FEE_RATE, 0.011)) AS FEE_AMT
    FROM   gd LEFT JOIN bp ON bp.MID = gd.MID
) s
ON (t.BC_DT = s.BC_DT AND t.MID = s.MID)
WHEN MATCHED THEN UPDATE
     SET t.TOT_AMT = s.TOT_AMT, t.FEE_AMT = s.FEE_AMT, t.VAT_AMT = ROUND(s.FEE_AMT * 0.1)
WHEN NOT MATCHED THEN INSERT (BC_DT, MID, TOT_AMT, FEE_AMT, VAT_AMT)
     VALUES (s.BC_DT, s.MID, s.TOT_AMT, s.FEE_AMT, ROUND(s.FEE_AMT * 0.1));