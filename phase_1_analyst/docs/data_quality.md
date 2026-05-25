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