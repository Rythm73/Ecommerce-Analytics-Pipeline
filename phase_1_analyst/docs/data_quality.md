# Olist Raw Data — Data Quality Findings

This document records data quality issues discovered during raw-layer profiling and constraint declaration. Each finding includes: the issue, evidence, decision, and reasoning. Findings are surfaced through PK/FK constraint failures and explicit profiling queries.

Findings are numbered `DQ-NNN` and referenced from the SQL constraint scripts and Phase 1 ADR.

---

## DQ-001 — order_reviews: review_id is not unique

**Discovered:** Day 2, attempting `PRIMARY KEY (review_id)` on `raw.order_reviews`.

**Evidence:**
- 789 distinct `review_id` values appear more than once
- 1,603 total rows are involved in duplication (~1.6% of the 99,224-row table)
- Duplicated rows contain *identical* review content (same score, same comment text, same timestamps) but reference *different* `order_id` values
- Some `review_id`s span up to 3 distinct orders

**Interpretation:** A single Olist buyer's review propagates across all of their concurrent orders with the same seller. The `review_id` identifies a logical review, but the row grain in this table is one row per (review, order) pair.

**Decision:** Use composite primary key `(review_id, order_id)` instead of `(review_id)` alone. Reflects the true grain of the source data without modifying any rows.

**Implication for downstream modeling:** When building `fact_reviews` in the star schema, the grain question becomes explicit: should a review be one fact row (deduplicated, joined to multiple orders via a bridge) or one fact row per (review, order)? Deferred to the star schema design (Day 5–6) and the ADR.

---

## DQ-002 — products: incomplete category translation

**Discovered:** Day 2, attempting `FOREIGN KEY (product_category_name)` on `raw.products → raw.product_category_name_translation`.

**Evidence:**
- 623 product rows (1.9% of 32,951) have no matching translation
- Breakdown:
  - 610 rows with `NULL` category — no category assigned in source
  - 10 rows with `portateis_cozinha_e_preparadores_de_alimentos` (Portuguese category exists in products, English translation missing)
  - 3 rows with `pc_gamer` (same pattern)

**Interpretation:** Olist's `product_category_name_translation` table is incomplete — it has 71 entries but the products table uses category names beyond those 71. Two categories in particular were never translated. Separately, 610 products were never assigned a category at all.

**Decision:** Do not enforce the foreign key in the `raw` schema. Document the gap.

**Reasoning:** The translation gap is a property of the source data. Enforcing the FK would require either deleting 13 product rows (data loss) or inserting fabricated translations into the translation table (violates "raw stays raw"). Both are inappropriate at this layer.

**Implication for downstream modeling:** In the `staging` layer, we will produce a cleaned `product_category_english` column using `COALESCE(translation.english, products.product_category_name, 'unknown')` — preserving the Portuguese name where no translation exists, and 'unknown' where the category is null. This will be documented in the staging transformation and the ADR.

---

## DQ-003 — orders: 'delivered' status without delivery timestamp

**Discovered:** Day 3, profiling `raw.orders` — cross-tab of `order_status` vs nullness of `order_delivered_customer_date`.

**Evidence:**
- 8 orders (0.008% of 96,478 delivered orders) have `order_status = 'delivered'` but `order_delivered_customer_date IS NULL`
- 7 of 8 have a populated `order_delivered_carrier_date` (handed to shipper but no customer confirmation captured)
- 1 of 8 (`2d858f451...`, May 2017) was never even shipped to a carrier yet is marked delivered

**Interpretation:** Olist's `order_status` is an independent logical field, not a derived flag from delivery timestamps. The `delivered` status can be set ahead of or without actual delivery confirmation.

**Decision:** Do not modify the raw data. Document for downstream consumers.

**Implication for downstream modeling:** Any "average delivery time" or "delivery SLA" metric must filter on `order_delivered_customer_date IS NOT NULL` rather than `order_status = 'delivered'`. The 8 orders are a tiny fraction but the principle matters: trust timestamps, not status, for time-based metrics.

---

## DQ-004 — orders: 'canceled' status with successful delivery timestamp

**Discovered:** Day 3, profiling `raw.orders` — same cross-tab as DQ-003.

**Evidence:**
- 6 orders have `order_status = 'canceled'` but a populated `order_delivered_customer_date`
- 5 of 6 are clustered in October–November 2016 (Olist's earliest months)
- In all 6 cases, the delivery timestamp precedes the implicit cancellation by days to weeks

**Interpretation:** The `canceled` status overloads two meanings in Olist's data: (a) orders that were canceled before fulfillment, and (b) orders that were delivered but later refunded/returned. The temporal clustering suggests this was specific to early-stage Olist process maturity; the practice likely tightened later.

**Decision:** Do not modify the raw data. Document for downstream consumers.

**Implication for downstream modeling:** Cancellation rate metrics calculated as `COUNT(*) WHERE status = 'canceled'` over-count true-cancellations by including post-delivery refunds. For a more accurate cancellation rate, separate the two cases using `order_delivered_customer_date IS NULL`. In the star schema, consider a derived flag like `cancellation_type` distinguishing pre-fulfillment cancels from post-delivery returns.


---

## DQ-005 — orders: `order_approved_at` timestamps after carrier handoff

**Discovered:** Day 3, profiling `raw.orders` — date logic checks on chronological ordering of order lifecycle timestamps.

**Evidence:**
- 1,359 orders (1.4% of those with both timestamps) have `order_approved_at > order_delivered_carrier_date`
- Lag distribution: median 17 hours, 75th percentile 26 hours, max 4,109 hours (~171 days)
- All 5 sample rows show the carrier event preceding the approved event by 1–4 days
- Pattern is consistent: purchase → carrier pickup → approved logged ~1 day later

**Interpretation:** The `order_approved_at` column does not mean "order was approved to ship." It most likely captures payment settlement / financial reconciliation, which happens *after* sellers have already shipped on pre-authorization. Olist's actual order-acceptance moment is closer to `order_purchase_timestamp` than to `order_approved_at`.

**Decision:** Do not modify the raw data. Document the column semantics for downstream consumers.

**Implication for downstream modeling:** 
- Do **not** use `order_approved_at` as the start of any delivery-time SLA calculation — it post-dates fulfillment events.
- The fulfillment clock should start at `order_purchase_timestamp` (the only timestamp guaranteed to precede physical events).
- In the staging or marts layer, consider renaming this column to `order_payment_settled_at` to reflect actual semantics.

---

## DQ-006 — orders: carrier handoff timestamps after customer delivery

**Discovered:** Day 3, profiling `raw.orders` — same date logic checks.

**Evidence:**
- 23 orders (0.02% of delivered orders) have `order_delivered_carrier_date > order_delivered_customer_date`
- Small absolute count; magnitude of inversion likely small (not investigated in detail)

**Interpretation:** Likely clock skew or late-arriving carrier events logged after delivery confirmation. Not a systematic process issue at this scale.

**Decision:** Do not modify. Filter these rows out of any "carrier-to-customer transit time" metric or use absolute difference.

**Implication for downstream modeling:** Any computation of `customer_date - carrier_date` should filter `WHERE carrier_date <= customer_date` or use `ABS()` to avoid negative durations contaminating averages.

---

## DQ-007 — order_items: 775 orders have no item-level records

**Discovered:** Day 3, profiling `raw.order_items` — items-per-order distribution revealed only 98,666 distinct orders despite 99,441 in `raw.orders`.

**Evidence:**
- 775 orders (0.78% of the orders table) have zero rows in `order_items`
- Breakdown by `order_status`:
  - `unavailable`: 603 (99% of all unavailable orders)
  - `canceled`: 164 (26% of all canceled orders)
  - `created`: 5 (100% of created orders)
  - `invoiced`: 2 (0.6% of invoiced — anomalous)
  - `shipped`: 1 (0.1% of shipped — anomalous)

**Interpretation:** Most of these are structurally expected — `unavailable`, `canceled`, and `created` orders represent pre-fulfillment states where line-item data may legitimately not exist. The 3 anomalous cases (2 invoiced, 1 shipped) cannot be explained by status alone and represent likely data corruption.

**Decision:** Do not modify the raw data. Document the pattern.

**Implication for downstream modeling:**
- Joining `orders` to `order_items` as INNER JOIN silently drops 775 orders. This is fine for *fulfillment* analysis (no items = nothing fulfilled) but wrong for *funnel* analysis (we'd miss the upstream conversion picture).
- In the star schema, `fact_order_items` (grain = order item) will naturally exclude these 775 orders. Order-level funnel analysis must use `fact_orders` (grain = order) which retains all 99,441 rows.
- The 3 anomalous "advanced status but no items" rows should be flagged in staging for monitoring but not deleted.

---

## DQ-008 — order_items: $0 freight clusters in 9 sellers, almost certainly bundled pricing

**Discovered:** Day 3, profiling `raw.order_items` — freight value distribution showed 383 items with $0 freight.

**Evidence:**
- 383 items (0.34% of 112,650) have `freight_value = 0`
- All 383 come from just 9 distinct sellers; 4 sellers account for 369 (96%) of them
- Top seller (`7d13fca1...`) has 158 zero-freight items alone
- Price distribution of zero-freight items: median $99.90 vs overall median $74.99 — 33% higher

**Interpretation:** This is not a data error. A small set of sellers appears to bundle freight into the listed product price (a common e-commerce competitive tactic). The higher median price of these items supports this hypothesis.

**Decision:** Do not modify the raw data. Document the pattern.

**Implication for downstream modeling:**
- Aggregate metrics like "total freight revenue" or "average freight per item" silently undercount by ~$0 × 383 items. The actual shipping cost was paid (bundled into price); the freight column just doesn't reflect it.
- For these sellers, treating `price + freight_value` as "total customer charge" is more accurate than analyzing the columns separately.
- In the staging layer, consider flagging sellers with `(zero_freight_items / total_items) > 5%` as "bundled-shipping sellers" so analysts can apply the right interpretation.

---

## DQ-009 — order_items: 4 shipping_limit_date values appear to be year-entry errors

**Discovered:** Day 3, profiling `raw.order_items` — shipping lead time distribution.

**Evidence:**
- 4 items have `shipping_limit_date` ~1,052–1,056 days after `order_purchase_timestamp`
- All 4 purchases occurred in March–May 2017; their shipping limits are dated Feb–April **2020**
- Pattern strongly suggests a year-entry error (2017 → 2020) at order creation time
- The next-longest lead time drops to 148 days, suggesting a clean break in the distribution

**Affected rows:**
- order_id `13bdf405f961a6deec817d817f5c6624` (purchased 2017-03-16, limit 2020-02-05)
- order_id `9c94a4ea2f7876660fa6f1b59b69c8e6` (purchased 2017-03-14, limit 2020-02-03)
- order_id `c2bb89b5c1dd978d507284be78a04cb2` (purchased 2017-05-23, limit 2020-04-09; 2 item rows)

**Decision:** Do not modify the raw data. Document and flag for review in staging.

**Implication for downstream modeling:** Any metric using `shipping_limit_date` (seller SLA adherence, deadline alignment) should either exclude these 4 rows or correct the year to 2017. Recommend handling in staging with a flagged correction.

---

## DQ-010 — order_payments: 3 rows with `payment_type = 'not_defined'`

**Discovered:** Day 3, profiling `raw.order_payments` — payment type distribution.

**Evidence:**
- 3 rows have `payment_type = 'not_defined'` (0.003% of 103,886 payments)
- All 3 have `payment_value = 0.0`
- All 3 are tied to `canceled` orders
- All 3 occurred within a 7-day window in August–September 2018

**Interpretation:** Placeholder payment records scaffolded when an order was initiated but never completed before cancellation. No actual transaction occurred.

**Decision:** Do not modify. Filter from any payment-method analysis using `WHERE payment_type != 'not_defined'`.

**Implication for downstream modeling:** Negligible. Just exclude from payment-mix breakdowns.

**Related observation (not a separate finding):** 6 additional zero-value payment rows exist on non-canceled orders, all with `payment_type = 'voucher'` and high `payment_sequential` values (3, 4, 13, 14). These are voucher accounting rows where the voucher balance was either zero or already spent on prior installments. The orders' total payments reconcile correctly to nonzero amounts. Filter out `payment_value = 0` rows for any "actual money flow" analysis.

---

## DQ-011 — order_payments: 2 credit_card payments with installments=0

**Discovered:** Day 3, profiling `raw.order_payments` — installment count distribution.

**Evidence:**
- 2 rows have `payment_installments = 0` (out of 103,886)
- Both are `credit_card` payments — credit card payments require ≥1 installment by definition
- Both have nonzero `payment_value` ($58.69 and $129.94)
- Both are tied to `delivered` orders, indicating real money flowed
- Both are `payment_sequential = 2` — secondary payment rows on orders that already have a primary payment

**Interpretation:** Likely data entry errors at payment-row creation. Both appear to be supplementary payments (top-ups, adjustments, or split charges) on otherwise normal orders where the installment count field was left unpopulated.

**Decision:** Do not modify the raw data. Flag in staging for correction (likely `COALESCE(installments, 1)` for credit_card rows).

**Implication for downstream modeling:** Any metric computing "average installments by payment type" must filter `WHERE payment_installments > 0` to avoid these 2 rows pulling the credit_card mean toward zero.

---

## DQ-012 — orders: 1 delivered order has no payment record

**Discovered:** Day 3, profiling `raw.order_payments` — payments-per-order distribution showed 99,440 distinct orders despite 99,441 in `raw.orders`.

**Evidence:**
- 1 order (`bfbd0f9bdef84302105ad712db648a6c`) has zero rows in `order_payments`
- Status: `delivered`
- Purchase date: 2016-09-15 — Olist's earliest operating period (matches the dataset's minimum `order_approved_at` date)

**Interpretation:** Likely a launch-era test or seed order that was logged in `orders` and marked delivered, but never had a corresponding payment row created. Single anomalous case, no pattern.

**Decision:** Do not modify. Document.

**Implication for downstream modeling:** Inner joins between `orders` and `order_payments` silently drop this order. Revenue and payment-mix aggregates will be undercounted by 1 order. Negligible impact, but if reconciliation between order count (99,441) and payment-having order count (99,440) ever surfaces, this is the explanation.

---

## DQ-013 — order_reviews: 547 orders have multiple review submissions

**Discovered:** Day 3, profiling `raw.order_reviews` — reviews-per-order distribution.

**Evidence:**
- 547 orders (0.55% of reviewed orders) have more than one review row
- 543 with 2 reviews; 4 with 3 reviews
- Sample inspection of 3-review orders confirms these are **different `review_id`s with different submission dates** (not row-level duplicates)
- Reviews on the same order can have **different scores** (e.g., order `03c939fd...` scored 3, 4, 3 across three separate reviews)

**Interpretation:** Distinct from DQ-001. DQ-001 was about a *single* review propagating to multiple orders. This finding is the inverse: a *single* order receiving multiple distinct review submissions, likely from buyers re-submitting after a changed experience, or via mechanisms allowing repeat submissions.

**Decision:** Do not modify the raw data. Document.

**Implication for downstream modeling:** 
- In `fact_reviews` (grain = review), all 99,224 rows are kept; "average review score per order" must be computed via aggregation (`AVG(score) GROUP BY order_id`).
- In `dim_order` enrichments (one-row-per-order), use the *most recent* review per order, or aggregate score (mean), with explicit choice documented in the ADR.
- This is the second axis of the reviews ↔ orders many-to-many relationship (DQ-001 was the first axis: one review → many orders). Both must be handled in star schema design.

---

## DQ-014 — products: 2 products with null physical attributes

**Discovered:** Day 3, profiling `raw.products` — co-null analysis of physical dimensions.

**Evidence:**
- 2 products have null `product_weight_g`, `product_length_cm`, `product_height_cm`, and `product_width_cm`
  - `09ff539a621711667c43eba6a3bd8466` — category `bebes` (babies), all physical attributes null
  - `5eb564652db742ff8f28759cd8d2652a` — null in both metadata AND physical (part of the 610-ghost-products group from DQ-002)
- The first case is the genuinely anomalous one: a catalogued product with a category but no shipping dimensions

**Interpretation:** Olist's product entry workflow allows physical attributes to be omitted. For 1 of the 2 cases, the product is otherwise fully described — likely a seller never filled in dimensions, and the gap was never flagged before the product went live.

**Decision:** Do not modify the raw data. Document.

**Implication for downstream modeling:** Any freight-estimation or volumetric-weight model needs to handle null dimensions explicitly. In staging, consider flagging these rows for review. Aggregate "average product weight by category" must use `WHERE product_weight_g IS NOT NULL` to avoid skew.

---

## DQ-015 — products: 4 products with 0g weight (template/placeholder values)

**Discovered:** Day 3, profiling `raw.products` — weight distribution.

**Evidence:**
- 4 products have `product_weight_g = 0`
- All 4 are in the same category: `cama_mesa_banho` (bed/table/bath linens)
- All 4 have **identical dimensions**: 30 × 25 × 30 cm
- Implies a copied product template with a placeholder weight that was never replaced

**Interpretation:** A seller (or sellers) copy-pasted a listing template with default-zero weight and identical placeholder dimensions, then created 4 separate product entries without filling in actual weights.

**Decision:** Do not modify the raw data. Document.

**Implication for downstream modeling:** Freight cost calculations using `product_weight_g` will undercharge for these 4 products. In staging, recommend either: (a) flagging as "weight unknown" and using a category-median imputation, or (b) excluding these 4 from weight-based aggregates. Negligible volume impact (4 of 32,951 products).

---

## DQ-016 — geolocation: 42 rows with coordinates outside Brazil's bounding box

**Discovered:** Day 3, profiling `raw.geolocation` — bounding box check against Brazil's actual lat/lng range (lat -34 to +5, lng -74 to -34).

**Evidence:**
- 42 rows (0.004% of 1,000,163) have coordinates outside Brazil
- Coordinates land in places like the Canary Islands, central Mexico, Spain, the U.S., and East Asia
- The associated `geolocation_state` values are valid Brazilian states; the *coordinates* are wrong, not the state attribution
- Sample anomaly: zip prefix `28155` (`santa maria`, RJ state) has two rows — one with valid Brazilian coords, one in Spain

**Interpretation:** Data entry errors. Likely causes: sign flips on lat/lng, swapped lat↔lng values, or coordinates from unrelated addresses bleeding into the wrong rows. The pattern of duplicate zip+city pairs with one valid and one invalid coordinate suggests these are spurious entries alongside correct ones, not systematic miscoding.

**Decision:** Do not modify the raw data. Filter in staging.

**Implication for downstream modeling:**
- Any distance-based analysis (delivery distance, seller-to-customer proximity, route optimization) must filter `geolocation_lat BETWEEN -34 AND 5 AND geolocation_lng BETWEEN -74 AND -34` to exclude these 42 rows.
- For dimensional modeling, when aggregating multiple lat/lng records per zip prefix into a single point, use the *median* (not mean) — medians are robust to these outliers; means would be pulled toward Mexico/Spain.
- In staging, recommend a `geolocation_clean` table that removes these 42 rows entirely.

---

## DQ-017 — geolocation: 45% of zip prefixes have multiple city name variants

**Discovered:** Day 3, profiling `raw.geolocation` — distinct city names per zip prefix.

**Evidence:**
- 8,556 zip prefixes (45.0% of 19,015) have more than one distinct `geolocation_city` value
- Up to 5 variants per zip — worst case: prefix `06900` spelled `embu-guacu`, `embu-guaçu`, `embu guaçu`, `embu guacu`, `embuguacu` for the same municipality (Embu-Guaçu, SP)
- Variants differ by: diacritics (`ç` vs `c`), separators (hyphen, space, none), and other normalization differences
- Result: `COUNT(DISTINCT geolocation_city)` returns 8,011 — likely 35–40% inflated relative to true distinct cities

**Interpretation:** City names were captured via uncontrolled free-text input, without normalization or a controlled vocabulary. This is endemic to Brazilian geographic data without canonical naming applied.

**Decision:** Do not modify the raw data. Critical issue to handle in staging.

**Implication for downstream modeling:**
- **Joins between `customers.customer_city` ↔ `geolocation.geolocation_city` are unreliable** — variants in either table won't match.
- For `dim_geolocation`: **must build on `zip_code_prefix` as the join key**, not city name. City is an *attribute* of the dimension, not its identifier.
- Recommended staging cleanup: normalize city strings via Unicode NFD normalization (strip accents), lowercase, replace separators with spaces, collapse whitespace. Map to canonical names via reference list if available.
- The 45% prevalence means this issue is structural, not edge-case.

---

## DQ-018 — geolocation: 1.05% of customer zips and 0.31% of seller zips lack geolocation coverage

**Discovered:** Day 3, profiling `raw.geolocation` — coverage check against zip prefixes used in `customers` and `sellers`.

**Evidence:**
- 157 distinct customer zip prefixes (1.05% of 14,994) are missing from `geolocation` → affects 278 customer rows (0.28%)
- 7 distinct seller zip prefixes (0.31% of 2,246) are missing → affects 7 seller rows (0.23%)
- Sample orphans are in real, large cities (Brasília, São Paulo, Curitiba, Porto Alegre) — Olist's geolocation table is incomplete, not just missing obscure locations

**Interpretation:** `geolocation` is not a complete coverage of Brazilian zip prefixes. Olist captured what was relevant at data export time, leaving small gaps. The gaps tend toward specific prefixes in otherwise-covered cities.

**Decision:** Do not modify the raw data. Document.

**Implication for downstream modeling:**
- Joining `customers`/`sellers` to `geolocation` via `LEFT JOIN` is mandatory — `INNER JOIN` would silently drop 278+7 = 285 records.
- For any distance-based computation (delivery distance, seller proximity), customers/sellers without geolocation must be either: (a) excluded with documentation, or (b) approximated using city-level centroid coordinates from same-city records.
- In `dim_geolocation`, consider a fallback row or sentinel value for "unknown coords" so dimension joins never break.