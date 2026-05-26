# Phase 1 SQL — File Index and Week 2 Plan

## Files in this directory

| File | Purpose | Status |
|---|---|---|
| `00_raw_constraints.sql` | PK and FK declarations on raw tables; surfaces DQ-001 and DQ-002 | ✅ Done (Day 2) |
| `01_star_schema.sql` | CREATE TABLE statements for the 9 marts-layer tables | ✅ Done (Day 6) |
| `02_*.sql` ... | Analytical queries for the 5 business questions | ⏳ Week 2 |

---

## Week 2 — Analytical query worklist

The 8 queries below answer the 5 business questions verified during Day 4's feasibility check (`notebooks/02_cross_table_and_outliers.ipynb`). Each maps to specific tables in the star schema and uses the staging cleanups documented in `data_quality.md`.

Queries assume the marts layer has been populated. In Phase 1 we have empty marts tables; Phase 2 populates them via dbt. Week 2 work uses raw + light-weight inline cleanups to prove each query *concept*; the dbt versions come later.

### Q1 — Revenue by category

| File | `02_revenue_by_category.sql` |
|---|---|
| Business question | Which product categories drive revenue? |
| Tables | `fact_order_items` + `dim_product` |
| Grain of result | One row per category |
| Key columns | `product_category_clean`, `SUM(total_item_value)`, `COUNT(DISTINCT order_id)` |
| DQ handled | DQ-002 (COALESCE applied in `dim_product.product_category_clean`) |

### Q2a — Delivery time vs review score (bucketed)

| File | `03_delivery_vs_review.sql` |
|---|---|
| Business question | How does delivery time correlate with review score? |
| Tables | `fact_orders` + `fact_reviews` |
| Grain of result | One row per delivery-time bucket |
| Key columns | `delivery_bucket`, `AVG(review_score)`, `pct_one_star` |
| DQ handled | DQ-019 (`WHERE NOT is_batch_resolved`), DQ-013 (review aggregation) |
| Note | Surfaces the 21-day patience cliff insight |

### Q2b — Delivery SLA report

| File | `04_delivery_sla_report.sql` |
|---|---|
| Business question | What share of orders meet, beat, or miss their delivery estimate? |
| Tables | `fact_orders` |
| Grain of result | One row per SLA bucket (early / on-time / 1-7d late / 7-30d late / 30+ late) |
| Key columns | `sla_bucket`, `order_count`, `pct_of_total` |

### Q3 — Cohort retention triangle

| File | `05_cohort_retention.sql` |
|---|---|
| Business question | Do new customers come back? At what rate over time? |
| Tables | `fact_orders` + `dim_customer` |
| Grain of result | One row per (cohort_month, months_since_first_purchase) |
| Key columns | `cohort_month`, `months_since_first_purchase`, `pct_active` |
| DQ handled | Uses `customer_unique_id`; exclude cohorts with <100 customers (early-Olist and late-2018 partial data) |
| Note | Expect sparse retention triangle given 3.4% repeat-buyer rate |

### Q4a — Seller underperformance ranking

| File | `06_seller_underperformance.sql` |
|---|---|
| Business question | Which sellers should be flagged for review? |
| Tables | `dim_seller` |
| Grain of result | One row per underperforming seller |
| Key columns | `seller_id`, `seller_total_items_sold`, `seller_avg_review_score`, `seller_one_star_rate` |
| Filter | `is_underperformer = TRUE` |
| Note | Pre-computed metrics on `dim_seller` make this a single-table query |

### Q4b — Seller performance × bundled shipping correlation

| File | `07_seller_bundled_shipping.sql` |
|---|---|
| Business question | Is bundled-shipping pricing correlated with seller performance? |
| Tables | `dim_seller` |
| Grain of result | 2x2 table of (is_bundled_shipping × is_underperformer) |
| Note | Day 4 observed seller `2709af9587...` appears in both groups; verify at population scale |

### Q5 — Order funnel + drop-off

| File | `08_order_funnel.sql` |
|---|---|
| Business question | Where do orders drop off in the lifecycle? |
| Tables | `fact_orders` |
| Grain of result | One row per `order_status` in funnel sequence |
| Key columns | `order_status`, `order_count`, `pct_of_total`, `cumulative_pct` |

### Q6 — Geographic revenue heatmap data

| File | `09_geo_revenue.sql` |
|---|---|
| Business question | Where does revenue concentrate geographically? |
| Tables | `fact_order_items` + `dim_customer` + `dim_geolocation` |
| Grain of result | One row per state (or zip prefix for fine-grained view) |
| Key columns | `customer_state`, `SUM(total_item_value)`, `order_count` |
| DQ handled | DQ-016 (median lat/lng), DQ-017 (use zip_code_prefix as join key, not city name) |
| Note | Confirms or contradicts the SP/RJ/MG concentration finding |

---

## Conventions for Week 2 queries

- One file per query — keeps each easy to test, version, and lift into a dbt model later
- File naming: `NN_descriptive_name.sql` where `NN` is execution order
- Each query starts with a comment block: business question, tables used, grain
- Inline staging cleanups: queries against raw should COALESCE / filter the same way the eventual staging models will
- Output should match the expected shape from Day 4's feasibility queries (these are the production versions of those one-off Day 4 checks)