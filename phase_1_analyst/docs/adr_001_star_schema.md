# ADR-001: Star Schema for Olist Retail Analytics

**Status:** Accepted

**Date:** Phase 1, Day 6

**Authors:** Gowthami R

---

## Context

The Olist Brazilian e-commerce dataset (~1.5M rows across 9 raw tables, 2016–2018) needs a dimensional model in the `marts` schema to serve five analytical questions:

1. Which product categories drive revenue?
2. How does delivery time correlate with review scores?
3. What does cohort retention look like for new customers?
4. Which sellers underperform on satisfaction and reliability?
5. Where do orders drop off in the lifecycle funnel?

The dimensional model also must accommodate **19 documented data quality findings** (see `data_quality.md`) without silently hiding them. Several findings affect grain, multi-grain relationships, or column semantics — these are not optional considerations.

This ADR records the design choices made during Phase 1 Day 5–6. Implementation (DDL, loading transformations) is deferred to Phase 2 (`raw → staging → marts` with dbt + Snowflake).

---

## Decision

A **Kimball-style star schema** with **4 fact tables** and **5 dimension tables**:

| Table | Type | Grain | Expected rows |
|---|---|---|---|
| `fact_orders` | Fact | one row per order | 99,441 |
| `fact_order_items` | Fact | one row per item per order | 112,650 |
| `fact_payments` | Fact | one row per payment installment | 103,886 |
| `fact_reviews` | Fact | one row per (review, order) pair | 99,224 |
| `dim_customer` | Dimension | one row per real customer | 96,096 |
| `dim_product` | Dimension | one row per product | 32,951 |
| `dim_seller` | Dimension | one row per seller | 3,095 |
| `dim_date` | Dimension | one row per date | ~850 |
| `dim_geolocation` | Dimension (outrigger) | one row per zip prefix | ~19,016 |

Diagram: `star_schema_v1.png`. Source DSL: `star_schema.dbml`.

---

## Key design decisions and reasoning

### D1. Four fact tables, not three

**Decision:** `fact_payments` is its own fact rather than rolled up onto `fact_orders`.

**Reasoning:** Olist's payment data has installment-level structure (composite PK on `(order_id, payment_sequential)`; some orders span 14+ rows for voucher splits). Rolling payments up to one row per order would collapse this structure and make analyses like "average installments by payment type" impossible from the marts layer. Findings DQ-010 and DQ-011 explicitly identify payment-row-level issues; the schema must be able to represent them. The cost is one additional table and one additional join for order-level payment totals — modest cost for preserving information.

**Alternative considered:** Roll payment data into `fact_orders` as columns (`primary_payment_type`, `total_payment_value`, `installments_count`). Rejected because it precludes the installment-level questions and contradicts the documented data quality investigation.

### D2. `fact_order_items` grain is item, not order

**Decision:** `fact_order_items` keeps the source grain `(order_id, order_item_id)`. `seller_key` and `product_key` live here, not on `fact_orders`.

**Reasoning:** An order can have items from multiple sellers (10% of orders have multiple items, some from different sellers). Putting `seller_key` on `fact_orders` would force grain compromises — either store multiple rows per order (breaking "one row per order" grain) or pick one seller and lose information. Keeping seller and product at the line-item level matches the natural shape of the data and serves the seller-performance and category-revenue questions directly.

### D3. `fact_reviews` grain is `(review_id, order_id)`, not deduplicated

**Decision:** Preserve the source grain. Each (review_id, order_id) pair gets a row — 99,224 rows.

**Reasoning:** Findings DQ-001 (789 review_ids span multiple orders) and DQ-013 (547 orders have multiple review_ids) together establish that reviews ↔ orders is **many-to-many on both axes**. Three grain alternatives were considered:

- *One row per `review_id`*: information loss — a review applied to 3 orders becomes 1 row, ambiguous attribution
- *One row per `order_id`*: lose review-level detail; requires score aggregation
- *One row per (review, order)*: **selected** — lossless, mirrors source, composite PK matches Day 2 constraint declaration

Analysts joining `fact_reviews` to other facts must use `SELECT DISTINCT review_id` or weighted averages where appropriate. The schema makes the M:M visible rather than hiding it.

### D4. Surrogate keys on all dimensions, natural keys preserved

**Decision:** Each dimension has an auto-incrementing `bigint` surrogate key (`customer_key`, `product_key`, etc.) AND retains its natural key as a column (`customer_unique_id`, `product_id`).

**Reasoning:** Kimball-standard approach. Surrogate keys are smaller (faster joins), insulate the warehouse from source key changes, and are required for any future Type 2 SCD migration. Natural keys are preserved for traceability back to raw — analysts auditing a metric can trace it to the source row.

### D5. Type 1 SCD throughout

**Decision:** All dimensions use Type 1 (overwrite changes; do not track history).

**Reasoning:** Olist's data is a closed 2016–2018 historical snapshot. There are no incoming updates; nothing changes over time. Type 2 history tracking adds complexity (effective_date columns, current_flag, surrogate keys per version) with zero benefit on a static dataset. If Phase 2 evolves toward live data ingestion, this decision will need revisiting.

### D6. `dim_customer` keyed on `customer_unique_id`, not `customer_id`

**Decision:** Each row in `dim_customer` represents one real person. `customer_id` (the per-order surrogate from Olist) is **not** the dimension key; it's a degenerate column on `fact_orders` for traceability.

**Reasoning:** Olist generates a fresh `customer_id` per order (99,441 distinct) but `customer_unique_id` (96,096 distinct) identifies the actual human. Q3 (cohort retention) is impossible to answer correctly without `customer_unique_id` as the dimensional anchor. Multiple `fact_orders` rows pointing to the same `dim_customer` row is normal and expected — that's how repeat purchases are represented.

### D7. `dim_geolocation` as an outrigger, with median aggregation

**Decision:** `dim_geolocation` is referenced by `dim_customer.customer_zip_code_prefix` and `dim_seller.seller_zip_code_prefix` rather than directly from facts. Lat/lng are aggregated to one row per zip prefix using **median**, not mean.

**Reasoning:** Two-part decision:

- *Outrigger pattern over denormalization:* Geolocation has 19,015 distinct zip prefixes with derived attributes. Copying these onto both `dim_customer` (96k rows) and `dim_seller` (3k rows) would be moderate duplication. Outrigger keeps one source of truth.
- *Median over mean:* Day 4 empirical analysis showed that DQ-016's 42 out-of-bounds coordinates corrupt the mean by >100km for 52 zip prefixes. Median is robust to these outliers without requiring upstream filtering. Recorded in DQ-016's implication section.

A sentinel "unknown" row is included for the 1.05% / 0.31% of customer/seller zips not present in source geolocation (DQ-018), so joins never fail.

### D8. Pre-computed metrics on `dim_seller`

**Decision:** `dim_seller` carries `seller_avg_review_score`, `seller_one_star_rate`, `seller_total_items_sold`, `is_underperformer`, `is_bundled_shipping` — computed from facts during marts build.

**Reasoning:** A "seller underperformance dashboard" (Q4) becomes a single-table query: `SELECT * FROM dim_seller WHERE is_underperformer = TRUE`. The alternative is computing these from `fact_order_items` + `fact_reviews` on every query, which is slower and harder for non-technical analysts to write. The cost is staging complexity (these columns must be refreshed when underlying data changes) and a violation of strict Kimball "dimensions don't hold metrics" doctrine. Pragmatic over pure.

### D9. Degenerate dimensions for low-cardinality fields

**Decision:** `order_status` (8 values), `payment_type` (5 values), `order_id` (used for traceability) are kept as columns on fact tables rather than as separate `dim_order_status`, `dim_payment_type` tables.

**Reasoning:** Dimensions with fewer than ~20 values typically don't justify the join overhead. Filtering becomes one inline `WHERE` clause instead of a join + filter. Standard Kimball pattern.

### D10. `dim_date` as a role-playing dimension

**Decision:** A single `dim_date` table is referenced by 7+ FK columns across facts (`purchase_date_key`, `delivered_date_key`, `shipping_limit_date_key`, `review_creation_date_key`). Each role uses a different alias when joined.

**Reasoning:** Creating separate `dim_purchase_date`, `dim_delivery_date`, etc. duplicates ~850 rows of calendar attributes per role. Standard Kimball role-playing pattern: one dim, multiple aliases. In SQL: `JOIN dim_date pd ON f.purchase_date_key = pd.date_key JOIN dim_date dd ON f.delivered_date_key = dd.date_key`.

### D11. Quality flags as boolean columns

**Decision:** Findings that require per-row identification (DQ-010, DQ-011, DQ-014, DQ-015, DQ-019) are surfaced as boolean flag columns (`is_voucher_zero_balance`, `is_batch_resolved`, etc.) on the relevant fact or dimension.

**Reasoning:** Analysts can filter cleanly (`WHERE NOT is_batch_resolved`) without needing to remember the underlying logic. Each flag's definition is documented in `data_quality.md`. This makes data quality issues *queryable* rather than *invisible*.

---

## Alternatives considered (and rejected)

- **Data Vault model:** rejected. Higher complexity, designed for very large enterprises with rapidly evolving sources. Olist is static and small.
- **OBT (One Big Table):** rejected. Some modern warehouses denormalize aggressively. Olist's multi-grain complexity (items, payments, reviews per order) makes OBT either lossy or absurdly wide.
- **Snowflake schema (normalized dimensions):** considered for `dim_product` (category as separate dim). Rejected — adds joins without meaningful benefit at this scale.

---

## Consequences

### What this enables

- All 5 business questions answerable in 1–3 joins (verified Day 4)
- Data quality findings traceable via boolean flags; not hidden
- Multi-grain analyses (item, order, payment, review) all supported at their natural grain
- Pre-computed metrics on `dim_seller` make underperformance dashboards trivial
- The 21-day "patience cliff" insight (Day 4) is queryable as `fact_orders.delivery_lateness_days × fact_reviews.review_score`

### What this makes harder

- **Cross-fact joins** require thinking about grain. Joining `fact_order_items` to `fact_reviews` on `order_id` will "fan out" reviews across each item — appropriate for some questions, wrong for others. Documented but requires analyst awareness.
- **Schema refresh cost.** Pre-computed columns on `dim_seller` and derived measures on facts must be recalculated when underlying data updates. Not an issue for the static Olist snapshot but would be for live data.
- **Outrigger join chains.** Customer-to-geolocation requires `fact_orders → dim_customer → dim_geolocation` — a three-hop join. Denormalization (copying lat/lng onto `dim_customer`) would reduce this to two hops at the cost of duplication. Revisit if query performance becomes an issue.

### Migration path if assumptions change

- If live data arrives → revisit D5 (Type 1 SCD) for `dim_customer` and `dim_product`
- If query performance lags → revisit D7 (outrigger) and consider denormalizing geolocation onto customer/seller dims
- If installment-level analysis turns out to be unnecessary → fact_payments could be collapsed into `fact_orders` (D1 reversal)

---

## References

- Data quality findings: `phase_1_analyst/docs/data_quality.md` (DQ-001 through DQ-019)
- Schema diagram: `phase_1_analyst/docs/star_schema_v1.png`
- Schema source: `phase_1_analyst/docs/star_schema.dbml`
- Feasibility verification: `phase_1_analyst/notebooks/02_cross_table_and_outliers.ipynb`
- Profiling: `phase_1_analyst/notebooks/01_data_profiling.ipynb`
- Raw schema constraints: `phase_1_analyst/sql/00_raw_constraints.sql`