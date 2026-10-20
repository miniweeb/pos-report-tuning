/* =====================================================================
   BAO CAO CHI TIET GD POS THEO DVCNT - RPT_POS_WEEKLY
   Version : V0 (ban dang chay PROD)
   Schema  : &&SCHEMA (da che)
   Binds   : :TU_NGAY, :DEN_NGAY (DATE), :CN_ID, :MID
   Mo ta   : chi tiet GD POS thanh cong trong ky, kem tai khoan lien ket,
             so lo, phi/VAT, doi soat NAPAS, ngay bao co PVOIL,
             GD goc cua GD huy va tong theo DVCNT.
   ===================================================================== */
WITH
/* ---------- 1. Tham so ---------- */
prm AS (
    SELECT :TU_NGAY  AS TU_DT
         , :DEN_NGAY AS DEN_DT
         , :CN_ID    AS CN_ID
         , :MID      AS MID
    FROM   DUAL
),
/* ---------- 2. GD POS trong ky ---------- */
gd AS (
    SELECT a.ID, a.GD_DT, a.POST_DT, a.MID, a.TID, a.PAN, a.PAN_MASK
         , a.GD_AMT, a.SETTL_AMT, a.CCY, a.AUTH_CD, a.RRN, a.CK_ID
         , a.GD_TYPE, a.BIN_ID, a.REQ_CAT, a.POST_STS, a.MCC
         , a.ORIG_DOC_ID, a.CARD_CTRY, a.MSG_CHNL
         , TRUNC(a.GD_DT)               AS GD_D
         , TO_CHAR(a.GD_DT,'HH24MISS')  AS GD_HMS
         , DECODE(a.REQ_CAT,'R',-1,1)   AS SIGN_F
    FROM   &&SCHEMA..W4_DOC_FULL a
    CROSS JOIN prm
    WHERE  TRUNC(a.GD_DT) BETWEEN prm.TU_DT AND prm.DEN_DT
      AND  a.STS      = 'A'
      AND  a.RET_CD   = 0
      AND  a.SRC_CHNL = 'P'
      AND  a.IS_AUTH  = 'N'
      AND  (prm.MID IS NULL OR a.MID = prm.MID)
),
/* ---------- 3. Chi nhanh ---------- */
cn AS (
    SELECT c.CN_ID, c.CN_NM, c.VUNG_CD
    FROM   &&SCHEMA..DM_CHI_NHANH c
),
/* ---------- 4. DVCNT theo chi nhanh ---------- */
dv AS (
    SELECT d.MID, d.MID_NM, d.CN_ID, d.MCC AS MID_MCC
         , cn.CN_NM, cn.VUNG_CD
    FROM   &&SCHEMA..W4_MERCHANT_DAILY d
    CROSS JOIN prm
    LEFT JOIN cn ON cn.CN_ID = d.CN_ID
    WHERE  d.STS = 'A'
      AND  (prm.CN_ID IS NULL OR SUBSTR(d.CN_ID,2,3) = prm.CN_ID)
),
/* ---------- 5. Danh muc ---------- */
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
/* ---------- 6. Phi theo chung tu ---------- */
fee AS (
    SELECT f.DOC_ID
         , SUM(f.FEE_AMT) AS FEE_AMT
         , SUM(f.VAT_AMT) AS VAT_AMT
    FROM   &&SCHEMA..W4_FEE_YEAR f
    WHERE  EXISTS (SELECT 1 FROM gd WHERE gd.ID = f.DOC_ID)
    GROUP BY f.DOC_ID
),
/* ---------- 7. Doi soat NAPAS, lay ban ghi moi nhat ---------- */
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
        WHERE  n.TRACE_NO <> '999999'
    )
    WHERE RN = 1
),
/* ---------- 8. Bao co PVOIL (bang hien tai + lich su) ---------- */
pv AS (
    SELECT b.RRN, b.AUTH_CD, b.CORE_STL_DT AS BC_DT
    FROM   &&SCHEMA..PVOIL_WS_TXN_INQ b
    CROSS JOIN prm
    WHERE  b.VAL_DT BETWEEN prm.TU_DT AND prm.DEN_DT + 1
    UNION
    SELECT h.RRN, h.AUTH_CD, h.CORE_STL_DT
    FROM   &&SCHEMA..PVOIL_WS_TXN_INQ_HIS h
    CROSS JOIN prm
    WHERE  h.VAL_DT BETWEEN prm.TU_DT AND prm.DEN_DT + 1
),
/* ---------- 9. Ghep chi tiet ---------- */
rpt AS (
    SELECT g.ID                                       AS DOC_ID
         , g.GD_D                                     AS GD_DT
         , TO_CHAR(g.GD_DT,'HH24:MI:SS')              AS GD_TIME
         , (SELECT MIN(p.BC_DT) FROM pv p
             WHERE p.RRN = g.RRN AND p.AUTH_CD = g.AUTH_CD) AS BC_DT
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
         , go.GOC_DT, go.GOC_AMT
         , CASE WHEN g.PAN_MASK LIKE '4%'
                 AND g.CARD_CTRY <> 'VNM' THEN 'Y' ELSE 'N' END AS THE_NN
         , g.MSG_CHNL
         , g.REQ_CAT, g.POST_STS
    FROM   gd  g
    JOIN   dv            ON dv.MID      = g.MID
    /* the -> tai khoan lien ket -> san pham */
    OUTER APPLY (
        SELECT t.HD_ID   AS TK_ID
             , p.PROD_NM AS CARD_TYPE
        FROM   &&SCHEMA..W4_ACNT_CONTRACT_DAILY c
        JOIN   &&SCHEMA..W4_ACNT_CONTRACT_DAILY t
               ON  t.ID     = c.TK_LK_ID
               AND t.STS    = 'A'
               AND t.HD_CAT = 'A'
        JOIN   &&SCHEMA..W4_APPL_PRODUCT_DAILY p
               ON  p.PROD_CD = c.PROD_CD
               AND p.STS     = 'A'
               AND p.PROD_CD NOT IN ('LC_CR_V_LT','LC_CR_V_LT_M')
        WHERE  c.HD_ID  = g.PAN
          AND  c.STS    = 'A'
          AND  c.HD_CAT = 'C'
          AND  c.REL_CD = '00'
    ) hd
    /* chu ky thiet bi -> so lo */
    OUTER APPLY (
        SELECT y.LO_ID
        FROM   &&SCHEMA..W4_DEVICE_REC_DAILY    v
        JOIN   &&SCHEMA..W4_ACQ_DEV_CYCLE_DAILY y
               ON y.DEV_ID = v.ID
        WHERE  v.TID   = g.TID
          AND  v.STS   = 'A'
          AND  y.CK_ID = g.CK_ID
    ) ck
    /* GD goc cua GD huy */
    OUTER APPLY (
        SELECT o.GD_DT AS GOC_DT, o.GD_AMT AS GOC_AMT
        FROM   &&SCHEMA..W4_DOC_FULL o
        WHERE  o.ID = g.ORIG_DOC_ID
          AND  g.REQ_CAT = 'R'
    ) go
    LEFT JOIN fee        ON fee.DOC_ID  = g.ID
    LEFT JOIN ns         ON ns.PAN      = g.PAN   AND ns.TID     = g.TID
                        AND ns.AUTH_CD  = g.AUTH_CD
                        AND ns.GD_AMT   = g.GD_AMT
                        AND ns.DS_D     = g.GD_D  AND ns.DS_HMS  = g.GD_HMS
    LEFT JOIN dm tt      ON tt.DM_TYPE  = 'TT'    AND tt.DM_CD   = g.GD_TYPE
    LEFT JOIN dm cy      ON cy.DM_TYPE  = 'CCY'   AND cy.DM_CD   = g.CCY
    LEFT JOIN dm bn      ON bn.DM_TYPE  = 'BIN'   AND bn.DM_CD   = TO_CHAR(g.BIN_ID)
    LEFT JOIN dm mc      ON mc.DM_TYPE  = 'MCC'   AND mc.DM_CD   = NVL(g.MCC, dv.MID_MCC)
),
/* ---------- 10. Chi so tinh toan ---------- */
calc AS (
    SELECT r.*
         , TRUNC(r.SETTL_AMT / NULLIF(r.GD_AMT,0))                 AS FX_RATE
         , CASE WHEN r.GD_AMT <> 0
                THEN ROUND((r.FEE_AMT + r.VAT_AMT) / r.GD_AMT * 100, 2) END AS FEE_PCT
         , r.GD_AMT - ABS(r.FEE_AMT) - ABS(r.VAT_AMT)             AS NET_AMT
    FROM   rpt r
),
/* ---------- 11. Tong theo DVCNT ---------- */
tong AS (
    SELECT c.MID
         , COUNT(*)       AS SO_GD_DVCNT
         , SUM(c.GD_AMT)  AS TOT_AMT_DVCNT
    FROM   calc c
    GROUP BY c.MID
)
/* ---------- Ket qua ---------- */
SELECT c.DOC_ID, c.GD_DT, c.GD_TIME, c.BC_DT, c.POST_DT
     , c.MID, c.MID_NM, c.CN_ID, c.CN_NM, c.VUNG_CD, c.TID, c.PAN_MASK
     , c.TK_ID, c.CARD_TYPE, c.LO_ID
     , c.GD_TYPE_NM, c.CCY_NM, c.BIN_NM, c.MCC_NM
     , c.GD_AMT, c.FX_RATE, c.SETTL_AMT, c.FEE_AMT, c.VAT_AMT
     , c.FEE_PCT, c.NET_AMT
     , c.AUTH_CD, c.RRN, c.TRACE_NO
     , c.GOC_DT, c.GOC_AMT, c.THE_NN, c.MSG_CHNL
     , DECODE(c.REQ_CAT,'P','Advice','R','Reversal','J','Adjustment') AS REQ_CAT
     , DECODE(c.POST_STS,'P','Posted','W','Waiting','R','Rejected',
                         'I','Inactive','C','Closed')           AS POST_STS
     , t.SO_GD_DVCNT, t.TOT_AMT_DVCNT
FROM   calc c
JOIN   tong t ON t.MID = c.MID
ORDER BY c.GD_DT, c.DOC_ID;