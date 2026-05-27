-- ============================================================
-- Olist Retail Analytics — Star Schema (marts layer)
-- 
-- Implements the dimensional model documented in:
--   - docs/adr_001_star_schema.md
--   - docs/star_schema_v1.png
--   - docs/star_schema.dbml
--
-- Tables defined here (in dependency order):
--   Dimensions: dim_date, dim_geolocation, dim_customer, dim_seller, dim_product
--   Facts:      fact_orders, fact_order_items, fact_payments, fact_reviews
--
-- This file creates empty tables only. Transformation logic
-- (raw -> staging -> marts) is implemented in Phase 2 with dbt.
-- ============================================================


-- ============================================================
-- DIMENSIONS
-- ============================================================

-- ------------------------------------------------------------
-- dim_date  --  role-playing dimension
-- ------------------------------------------------------------
CREATE TABLE marts.dim_date (
    date_key            INTEGER PRIMARY KEY,            -- format YYYYMMDD
    full_date           DATE NOT NULL UNIQUE,
    year                INTEGER NOT NULL,
    quarter             INTEGER NOT NULL,
    month               INTEGER NOT NULL,
    month_name          VARCHAR(20) NOT NULL,
    day                 INTEGER NOT NULL,
    day_of_week         INTEGER NOT NULL,               -- 0=Sun..6=Sat
    day_name            VARCHAR(20) NOT NULL,
    iso_week            INTEGER NOT NULL,
    iso_year            INTEGER NOT NULL,
    is_weekend          BOOLEAN NOT NULL,
    is_brazilian_holiday BOOLEAN NOT NULL DEFAULT FALSE
);

COMMENT ON TABLE marts.dim_date IS 
    'Calendar dimension. ~850 rows covering 2016-09-01 to 2018-12-31. Role-playing across 7+ FKs.';


-- ------------------------------------------------------------
-- dim_geolocation  --  outrigger dimension
-- ------------------------------------------------------------
CREATE TABLE marts.dim_geolocation (
    geolocation_key         BIGSERIAL PRIMARY KEY,
    zip_code_prefix         VARCHAR(10) NOT NULL UNIQUE,
    city_canonical          VARCHAR(100),
    city_raw_variants_count INTEGER,
    state                   VARCHAR(2),
    latitude_median         NUMERIC(10, 7),
    longitude_median        NUMERIC(10, 7),
    is_unknown              BOOLEAN NOT NULL DEFAULT FALSE
);

COMMENT ON TABLE marts.dim_geolocation IS 
    'Outrigger dimension. ~19,016 rows incl. 1 sentinel for uncovered zips (DQ-018). Median aggregation per DQ-016.';
COMMENT ON COLUMN marts.dim_geolocation.city_canonical IS 
    'Normalized city name (accents stripped, lowercase). DQ-017 mitigation.';
COMMENT ON COLUMN marts.dim_geolocation.is_unknown IS 
    'TRUE for sentinel row used when customer/seller zip not in source geolocation.';


-- ------------------------------------------------------------
-- dim_customer
-- ------------------------------------------------------------
CREATE TABLE marts.dim_customer (
    customer_key                 BIGSERIAL PRIMARY KEY,
    customer_unique_id           VARCHAR(50) NOT NULL UNIQUE, -- natural key (real person)
    customer_zip_code_prefix     VARCHAR(10),
    customer_city                VARCHAR(100),
    customer_state               VARCHAR(2),
    customer_first_purchase_date DATE,

    CONSTRAINT fk_dim_customer_geo FOREIGN KEY (customer_zip_code_prefix)
        REFERENCES marts.dim_geolocation(zip_code_prefix)
);

COMMENT ON TABLE marts.dim_customer IS 
    'SCD Type 1. 96,096 rows. One per real person via customer_unique_id, not per-order customer_id.';


-- ------------------------------------------------------------
-- dim_seller
-- ------------------------------------------------------------
CREATE TABLE marts.dim_seller (
    seller_key              BIGSERIAL PRIMARY KEY,
    seller_id               VARCHAR(50) NOT NULL UNIQUE,     -- natural key
    seller_zip_code_prefix  VARCHAR(10),
    seller_city             VARCHAR(100),
    seller_state            VARCHAR(2),
    seller_first_sale_date  DATE,
    seller_total_items_sold INTEGER,
    seller_avg_review_score NUMERIC(3, 2),
    seller_one_star_rate    NUMERIC(5, 2),
    is_bundled_shipping     BOOLEAN NOT NULL DEFAULT FALSE,
    is_underperformer       BOOLEAN NOT NULL DEFAULT FALSE,

    CONSTRAINT fk_dim_seller_geo FOREIGN KEY (seller_zip_code_prefix)
        REFERENCES marts.dim_geolocation(zip_code_prefix)
);

COMMENT ON TABLE marts.dim_seller IS 
    'SCD Type 1. 3,095 rows. Pre-computed metrics support Q4 (seller underperformance).';
COMMENT ON COLUMN marts.dim_seller.is_underperformer IS 
    'Derived: avg_review_score < 3 AND total_items_sold > 20.';
COMMENT ON COLUMN marts.dim_seller.is_bundled_shipping IS 
    'DQ-008: seller has any $0-freight items.';


-- ------------------------------------------------------------
-- dim_product
-- ------------------------------------------------------------
CREATE TABLE marts.dim_product (
    product_key                       BIGSERIAL PRIMARY KEY,
    product_id                        VARCHAR(50) NOT NULL UNIQUE,
    product_category_name_portuguese  VARCHAR(100),
    product_category_name_english     VARCHAR(100),
    product_category_clean            VARCHAR(100),
    product_weight_g                  NUMERIC(10, 2),
    product_length_cm                 NUMERIC(8, 2),
    product_height_cm                 NUMERIC(8, 2),
    product_width_cm                  NUMERIC(8, 2),
    product_volume_cm3                NUMERIC(15, 2),
    is_metadata_complete              BOOLEAN NOT NULL DEFAULT TRUE,
    is_dimensions_missing             BOOLEAN NOT NULL DEFAULT FALSE,
    is_weight_zero_placeholder        BOOLEAN NOT NULL DEFAULT FALSE
);

COMMENT ON TABLE marts.dim_product IS 
    'SCD Type 1. 32,951 rows. product_category_clean = COALESCE(english, portuguese, ''unknown'') per DQ-002.';


-- ============================================================
-- FACTS
-- ============================================================

-- ------------------------------------------------------------
-- fact_orders  --  grain: one row per order
-- ------------------------------------------------------------
CREATE TABLE marts.fact_orders (
    order_key              BIGSERIAL PRIMARY KEY,
    order_id               VARCHAR(50) NOT NULL UNIQUE,     -- degenerate dimension
    customer_key           BIGINT NOT NULL,
    purchase_date_key      INTEGER NOT NULL,
    delivered_date_key     INTEGER,                          -- nullable (not all orders delivered)
    order_status           VARCHAR(20) NOT NULL,             -- degenerate
    delivery_days_actual   NUMERIC(8, 2),
    delivery_lateness_days NUMERIC(8, 2),
    total_order_value      NUMERIC(12, 2),                   -- denormalized from fact_payments
    is_delivered           BOOLEAN NOT NULL,
    is_canceled            BOOLEAN NOT NULL,
    is_batch_resolved      BOOLEAN NOT NULL DEFAULT FALSE,   -- DQ-019

    CONSTRAINT fk_fact_orders_customer FOREIGN KEY (customer_key)
        REFERENCES marts.dim_customer(customer_key),
    CONSTRAINT fk_fact_orders_purchase_date FOREIGN KEY (purchase_date_key)
        REFERENCES marts.dim_date(date_key),
    CONSTRAINT fk_fact_orders_delivered_date FOREIGN KEY (delivered_date_key)
        REFERENCES marts.dim_date(date_key)
);

COMMENT ON TABLE marts.fact_orders IS 
    'Grain: one row per order. 99,441 rows. Supports Q2 (delivery vs review), Q3 (cohort), Q5 (funnel).';


-- ------------------------------------------------------------
-- fact_order_items  --  grain: one row per item per order
-- ------------------------------------------------------------
CREATE TABLE marts.fact_order_items (
    order_item_key          BIGSERIAL PRIMARY KEY,
    order_id                VARCHAR(50) NOT NULL,             -- degenerate
    order_item_id           VARCHAR(20) NOT NULL,             -- degenerate
    product_key             BIGINT NOT NULL,
    seller_key              BIGINT NOT NULL,
    purchase_date_key       INTEGER NOT NULL,
    shipping_limit_date_key INTEGER,
    price                   NUMERIC(10, 2) NOT NULL,
    freight_value           NUMERIC(10, 2) NOT NULL,
    total_item_value        NUMERIC(10, 2) NOT NULL,
    freight_to_price_ratio  NUMERIC(8, 4),

    CONSTRAINT uq_fact_order_items_natural UNIQUE (order_id, order_item_id),
    CONSTRAINT fk_fact_items_product FOREIGN KEY (product_key)
        REFERENCES marts.dim_product(product_key),
    CONSTRAINT fk_fact_items_seller FOREIGN KEY (seller_key)
        REFERENCES marts.dim_seller(seller_key),
    CONSTRAINT fk_fact_items_purchase_date FOREIGN KEY (purchase_date_key)
        REFERENCES marts.dim_date(date_key),
    CONSTRAINT fk_fact_items_shipping_date FOREIGN KEY (shipping_limit_date_key)
        REFERENCES marts.dim_date(date_key)
);

COMMENT ON TABLE marts.fact_order_items IS 
    'Grain: one row per item per order. 112,650 rows. Supports Q1 (revenue), Q4 (seller perf).';


-- ------------------------------------------------------------
-- fact_payments  --  grain: one row per payment installment
-- ------------------------------------------------------------
CREATE TABLE marts.fact_payments (
    payment_key                  BIGSERIAL PRIMARY KEY,
    order_id                     VARCHAR(50) NOT NULL,
    payment_sequential           INTEGER NOT NULL,
    purchase_date_key            INTEGER NOT NULL,
    payment_type                 VARCHAR(20) NOT NULL,        -- degenerate
    payment_installments         INTEGER NOT NULL,
    payment_value                NUMERIC(12, 2) NOT NULL,
    is_not_defined_placeholder   BOOLEAN NOT NULL DEFAULT FALSE,  -- DQ-010
    is_voucher_zero_balance      BOOLEAN NOT NULL DEFAULT FALSE,  -- DQ-010 addendum
    is_installments_data_error   BOOLEAN NOT NULL DEFAULT FALSE,  -- DQ-011

    CONSTRAINT uq_fact_payments_natural UNIQUE (order_id, payment_sequential),
    CONSTRAINT fk_fact_payments_purchase_date FOREIGN KEY (purchase_date_key)
        REFERENCES marts.dim_date(date_key)
);

COMMENT ON TABLE marts.fact_payments IS 
    'Grain: one row per payment installment. 103,886 rows. Installment-level structure preserved per ADR D1.';


-- ------------------------------------------------------------
-- fact_reviews  --  grain: one row per (review_id, order_id)
-- ------------------------------------------------------------
CREATE TABLE marts.fact_reviews (
    review_key                BIGSERIAL PRIMARY KEY,
    review_id                 VARCHAR(50) NOT NULL,
    order_id                  VARCHAR(50) NOT NULL,
    review_creation_date_key  INTEGER NOT NULL,
    review_score              INTEGER NOT NULL,
    response_lag_hours        NUMERIC(10, 2),
    has_comment               BOOLEAN NOT NULL DEFAULT FALSE,
    is_score_extreme          BOOLEAN NOT NULL DEFAULT FALSE,

    CONSTRAINT uq_fact_reviews_natural UNIQUE (review_id, order_id),
    CONSTRAINT chk_review_score CHECK (review_score BETWEEN 1 AND 5),
    CONSTRAINT fk_fact_reviews_date FOREIGN KEY (review_creation_date_key)
        REFERENCES marts.dim_date(date_key)
);

COMMENT ON TABLE marts.fact_reviews IS 
    'Grain: one row per (review, order) pair. 99,224 rows. M:M reviews-orders captured via composite natural key (DQ-001, DQ-013).';