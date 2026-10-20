/* V1 - BAO CAO CHI TIET GD POS THEO DVCNT (BAN TOI UU)
   Schema  : &&SCHEMA (da che)
   Binds   : :TU_NGAY, :DEN_NGAY (DATE), :CN_ID, :MID
   Ket qua : doi chieu o sql/05_reconcile
   Thay doi so voi V0:
     1. gd  : TRUNC(GD_DT) BETWEEN -> GD_DT >= :TU AND GD_DT < :DEN + 1
              (cot tran -> partition pruning 32 -> 1)
     2. hd, ck, gd_goc: OUTER APPLY (chay theo tung dong)
              -> CTE theo tap tren danh sach khoa k_pan / k_tid / k_goc + hash join
     3. ns  : ROW_NUMBER tren ca bang NAPAS -> cat theo ky truoc khi sort
     4. pv  : UNION (sort khu trung) -> UNION ALL + GROUP BY; scalar subquery
              lay BC_DT -> LEFT JOIN
     5. dm  : so sanh DM_CD (VARCHAR) = GD_TYPE (NUMBER) bi ep kieu ngam
              -> TO_CHAR ve phia GD
     6. dv  : SUBSTR(CN_ID,2,3) -> virtual column CN3_ID co index
     7. tong: GROUP BY + join lai -> analytic COUNT/SUM OVER (PARTITION BY MID) */
WITH
/* A. THAM SO */
/* 1. Tham so ky bao cao */
prm AS (
    SELECT :TU_NGAY      AS TU_DT
         , :DEN_NGAY + 1 AS DEN_DT
         , :CN_ID        AS CN_ID
         , :MID          AS MID
    FROM   DUAL
),

/* B. FACT TRONG KY */
/* 2. GD POS trong ky (co pruning) */
gd AS (
    SELECT /*+ NO_MERGE DYNAMIC_SAMPLING(a 4) */
           a.ID, a.GD_DT, a.POST_DT, a.MID, a.TID, a.PAN, a.PAN_MASK
         , a.GD_AMT, a.SETTL_AMT, a.CCY, a.AUTH_CD, a.RRN, a.CK_ID
         , a.GD_TYPE, a.BIN_ID, a.REQ_CAT, a.POST_STS, a.MCC
         , a.ORIG_DOC_ID, a.CARD_CTRY, a.MSG_CHNL
         , TRUNC(a.GD_DT)               AS GD_D
         , TO_CHAR(a.GD_DT,'HH24MISS')  AS GD_HMS
         , DECODE(a.REQ_CAT,'R',-1,1)   AS SIGN_F
    FROM   &&SCHEMA..W4_DOC_FULL a
    CROSS JOIN prm
    WHERE  a.GD_DT   >= prm.TU_DT                  -- cot tran -> Pstart=KEY
      AND  a.GD_DT   <  prm.DEN_DT
      AND  a.STS      = 'A'                        -- NOT NULL, bo NVL
      AND  a.RET_CD   = 0
      AND  a.SRC_CHNL = 'P'
      AND  a.IS_AUTH  = 'N'
      AND  (prm.MID IS NULL OR a.MID = prm.MID)
),
/* 3. Danh sach khoa can tra cuu (thu hep dim) */
k_pan AS (
    SELECT DISTINCT PAN FROM gd
),
k_tid AS (
    SELECT DISTINCT TID, CK_ID FROM gd
),
k_goc AS (
    SELECT ID AS DOC_ID, ORIG_DOC_ID
    FROM   gd
    WHERE  REQ_CAT = 'R'
      AND  ORIG_DOC_ID IS NOT NULL
),

/* C. DIMENSION */
/* 4. Chi nhanh */
cn AS (
    SELECT c.CN_ID, c.CN_NM, c.VUNG_CD
    FROM   &&SCHEMA..DM_CHI_NHANH c
),
/* 5. DVCNT theo chi nhanh (virtual column CN3_ID) */
dv AS (
    SELECT d.MID, d.MID_NM, d.CN_ID, d.CN3_ID, d.MCC AS MID_MCC
         , cn.CN_NM, cn.VUNG_CD
    FROM   &&SCHEMA..W4_MERCHANT_DAILY d
    CROSS JOIN prm
    LEFT JOIN cn ON cn.CN_ID = d.CN_ID
    WHERE  d.STS = 'A'
      AND  (prm.CN_ID IS NULL OR d.CN3_ID = prm.CN_ID)
),
/* 6. The -> tai khoan lien ket -> san pham */
hd AS (
    SELECT /*+ NO_MERGE LEADING(k c) USE_NL(c) */
           c.HD_ID            AS PAN
         , t.HD_ID            AS TK_ID
         , p.PROD_NM          AS CARD_TYPE
    FROM   k_pan k
    JOIN   &&SCHEMA..W4_ACNT_CONTRACT_DAILY c
           ON  c.HD_ID   = k.PAN
           AND c.STS     = 'A'
           AND c.HD_CAT  = 'C'
           AND c.REL_CD  = '00'
    JOIN   &&SCHEMA..W4_ACNT_CONTRACT_DAILY t
           ON  t.ID      = c.TK_LK_ID
           AND t.STS     = 'A'
           AND t.HD_CAT  = 'A'
    JOIN   &&SCHEMA..W4_APPL_PRODUCT_DAILY p
           ON  p.PROD_CD = c.PROD_CD
           AND p.STS     = 'A'
           AND p.PROD_CD NOT IN ('LC_CR_V_LT','LC_CR_V_LT_M')
),
/* 7. Chu ky thiet bi -> so lo (index-only I2) */
ck AS (
    SELECT /*+ NO_MERGE */
           k.TID, k.CK_ID, y.LO_ID
    FROM   k_tid k
    JOIN   &&SCHEMA..W4_DEVICE_REC_DAILY    v
           ON  v.TID = k.TID
           AND v.STS = 'A'
    JOIN   &&SCHEMA..W4_ACQ_DEV_CYCLE_DAILY y
           ON  y.DEV_ID = v.ID
           AND y.CK_ID  = k.CK_ID
),
/* 8. Danh muc nho gop 1 CTE */
dm AS (
    SELECT 'TT'  AS DM_TYPE, TO_CHAR(ID) AS DM_CD, TT_NM  AS DM_NM
    FROM   &&SCHEMA..W4_TRANS_TYPE_DAILY WHERE STS = 'A'
    UNION ALL
    SELECT 'CCY', CCY_CD, CCY_NM
    FROM   &&SCHEMA..W4_CURRENCY_DAILY   WHERE STS = 'A'
    UNION ALL
    SELECT 'BIN', TO_CHAR(ID), BIN_NM
    FROM   &&SCHEMA..W4_BIN_TABLE_V
    UNION ALL
    SELECT 'MCC', MCC, MCC_NM
    FROM   &&SCHEMA..DM_MCC
),

/* D. DU LIEU DOI SOAT / PHI */
/* 9. Phi theo chung tu (chi chung tu trong ky) */
fee AS (
    SELECT /*+ USE_HASH(f) */
           f.DOC_ID
         , SUM(f.FEE_AMT) AS FEE_AMT
         , SUM(f.VAT_AMT) AS VAT_AMT
    FROM   &&SCHEMA..W4_FEE_YEAR f
    WHERE  EXISTS (SELECT 1 FROM gd WHERE gd.ID = f.DOC_ID)
    GROUP BY f.DOC_ID
),
/* 10. Doi soat NAPAS trong ky, khu trung */
ns AS (
    SELECT PAN, TID, AUTH_CD, GD_AMT, DS_D, DS_HMS, TRACE_NO
    FROM (
        SELECT n.PAN, n.TID, n.AUTH_CD, n.GD_AMT
             , n.DS_DT  AS DS_D
             , n.DS_HMS
             , n.TRACE_NO
             , ROW_NUMBER() OVER (PARTITION BY n.PAN, n.TID, n.AUTH_CD, n.GD_AMT,
                                               n.DS_DT, n.DS_HMS
                                  ORDER BY n.TRACE_NO DESC) AS RN
        FROM   &&SCHEMA..W4_OPT_NAPAS_RECONCILE_TRANS n
        CROSS JOIN prm
        WHERE  n.DS_DT    >= prm.TU_DT
          AND  n.DS_DT    <  prm.DEN_DT
          AND  n.TRACE_NO <> '999999'
    )
    WHERE RN = 1
),
/* 11. Bao co PVOIL trong ky (bang hien tai + lich su) */
pv_raw AS (
    SELECT b.RRN, b.AUTH_CD, b.CORE_STL_DT
    FROM   &&SCHEMA..PVOIL_WS_TXN_INQ b
    CROSS JOIN prm
    WHERE  b.VAL_DT >= prm.TU_DT
      AND  b.VAL_DT <  prm.DEN_DT
    UNION ALL
    SELECT h.RRN, h.AUTH_CD, h.CORE_STL_DT
    FROM   &&SCHEMA..PVOIL_WS_TXN_INQ_HIS h
    CROSS JOIN prm
    WHERE  h.VAL_DT >= prm.TU_DT
      AND  h.VAL_DT <  prm.DEN_DT
),
pv AS (
    SELECT RRN, AUTH_CD, MIN(CORE_STL_DT) AS BC_DT
    FROM   pv_raw
    GROUP BY RRN, AUTH_CD
),
/* 12. GD goc cua giao dich huy (1 join thay 2 subquery) */
gd_goc AS (
    SELECT /*+ LEADING(k) USE_NL(o) */
           k.DOC_ID
         , o.GD_DT  AS GOC_DT
         , o.GD_AMT AS GOC_AMT
    FROM   k_goc k
    JOIN   &&SCHEMA..W4_DOC_FULL o
           ON o.ID = k.ORIG_DOC_ID
),

/* E. GHEP + TINH TOAN */
/* 13. Ghep chi tiet */
rpt AS (
    SELECT /*+ LEADING(g dv) USE_HASH(dv)
               USE_HASH(ns) SWAP_JOIN_INPUTS(ns)
               USE_HASH(pv) SWAP_JOIN_INPUTS(pv)
               USE_HASH(fee) USE_HASH(hd) USE_HASH(ck) USE_HASH(gg)
               USE_HASH(tt) USE_HASH(cy) USE_HASH(bn) USE_HASH(mc) */
           g.ID                                       AS DOC_ID
         , g.GD_D                                     AS GD_DT
         , TO_CHAR(g.GD_DT,'HH24:MI:SS')              AS GD_TIME
         , pv.BC_DT
         , g.POST_DT
         , g.MID, dv.MID_NM, dv.CN_ID, dv.CN_NM, dv.VUNG_CD
         , g.TID
         , g.PAN_MASK
         , hd.TK_ID
         , hd.CARD_TYPE
         , NVL(ck.LO_ID,'999999')                     AS LO_ID
         , tt.DM_NM                                   AS GD_TYPE_NM
         , cy.DM_NM                                   AS CCY_NM
         , bn.DM_NM                                   AS BIN_NM
         , mc.DM_NM                                   AS MCC_NM
         , g.GD_AMT, g.SETTL_AMT
         , NVL(g.SIGN_F * fee.FEE_AMT, 0)             AS FEE_AMT
         , ROUND(NVL(g.SIGN_F * fee.VAT_AMT,
                     NVL(g.SIGN_F * fee.FEE_AMT, 0) * 0.1)) AS VAT_AMT
         , g.AUTH_CD, g.RRN
         , ns.TRACE_NO
         , gg.GOC_DT, gg.GOC_AMT
         , CASE WHEN g.PAN_MASK LIKE '4%'
                 AND g.CARD_CTRY <> 'VNM' THEN 'Y' ELSE 'N' END AS THE_NN
         , g.MSG_CHNL
         , g.REQ_CAT, g.POST_STS
    FROM   gd  g
    JOIN   dv            ON dv.MID      = g.MID
    LEFT JOIN hd         ON hd.PAN      = g.PAN
    LEFT JOIN ck         ON ck.TID      = g.TID   AND ck.CK_ID   = g.CK_ID
    LEFT JOIN fee        ON fee.DOC_ID  = g.ID
    LEFT JOIN ns         ON ns.PAN      = g.PAN   AND ns.TID     = g.TID
                        AND ns.AUTH_CD  = g.AUTH_CD
                        AND ns.GD_AMT   = g.GD_AMT
                        AND ns.DS_D     = g.GD_D  AND ns.DS_HMS  = g.GD_HMS
    LEFT JOIN pv         ON pv.RRN      = g.RRN   AND pv.AUTH_CD = g.AUTH_CD
    LEFT JOIN gd_goc gg  ON gg.DOC_ID   = g.ID
    LEFT JOIN dm tt      ON tt.DM_TYPE  = 'TT'    AND tt.DM_CD   = TO_CHAR(g.GD_TYPE)
    LEFT JOIN dm cy      ON cy.DM_TYPE  = 'CCY'   AND cy.DM_CD   = g.CCY
    LEFT JOIN dm bn      ON bn.DM_TYPE  = 'BIN'   AND bn.DM_CD   = TO_CHAR(g.BIN_ID)
    LEFT JOIN dm mc      ON mc.DM_TYPE  = 'MCC'   AND mc.DM_CD   = NVL(g.MCC, dv.MID_MCC)
),
/* 14. Chi so tinh toan */
calc AS (
    SELECT r.*
         , TRUNC(r.SETTL_AMT / NULLIF(r.GD_AMT,0))                 AS FX_RATE
         , CASE WHEN r.GD_AMT <> 0
                THEN ROUND((r.FEE_AMT + r.VAT_AMT) / r.GD_AMT * 100, 2) END AS FEE_PCT
         , r.GD_AMT - ABS(r.FEE_AMT) - ABS(r.VAT_AMT)             AS NET_AMT
    FROM   rpt r
),
/* 15. Tong theo DVCNT bang analytic (khong GROUP BY + join lai) */
fin AS (
    SELECT c.*
         , COUNT(*)        OVER (PARTITION BY c.MID) AS SO_GD_DVCNT
         , SUM(c.GD_AMT)   OVER (PARTITION BY c.MID) AS TOT_AMT_DVCNT
    FROM   calc c
)
/* F. KET QUA */
SELECT f.DOC_ID, f.GD_DT, f.GD_TIME, f.BC_DT, f.POST_DT
     , f.MID, f.MID_NM, f.CN_ID, f.CN_NM, f.VUNG_CD, f.TID, f.PAN_MASK
     , f.TK_ID, f.CARD_TYPE, f.LO_ID
     , f.GD_TYPE_NM, f.CCY_NM, f.BIN_NM, f.MCC_NM
     , f.GD_AMT, f.FX_RATE, f.SETTL_AMT, f.FEE_AMT, f.VAT_AMT
     , f.FEE_PCT, f.NET_AMT
     , f.AUTH_CD, f.RRN, f.TRACE_NO
     , f.GOC_DT, f.GOC_AMT, f.THE_NN, f.MSG_CHNL
     , DECODE(f.REQ_CAT,'P','Advice','R','Reversal','J','Adjustment') AS REQ_CAT
     , DECODE(f.POST_STS,'P','Posted','W','Waiting','R','Rejected',
                         'I','Inactive','C','Closed')           AS POST_STS
     , f.SO_GD_DVCNT, f.TOT_AMT_DVCNT
FROM   fin f
ORDER BY f.GD_DT, f.DOC_ID;
