# Luong bao cao tuan (sau toi uu)

```mermaid
flowchart LR
  A[Nguon: Core the / NAPAS] --> B[Staging<br/>STG_W4_POS_TXN_WEEKLY]
  B --> C[Tinh phi<br/>sql/04_merge - 48s]
  C --> D[Bao cao<br/>sql/02_rewrite V1 - 1m55s]
  D --> E[Doi soat<br/>sql/05_reconcile]
  E --> F[Xuat file / SFTP]
```
Scheduler: 02:00 thu Hai. Tong ~4m 10s.
