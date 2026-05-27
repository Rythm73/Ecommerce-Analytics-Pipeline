-- ============================================================
-- Raw schema constraints
-- Purpose: declare structural rules and surface data quality issues
-- ============================================================

-- --- Primary keys ---

-- customers: customer_id is the per-order surrogate (one per order, not per person)
ALTER TABLE raw.customers ADD PRIMARY KEY (customer_id);

-- orders: order_id is the natural transaction identifier
ALTER TABLE raw.orders ADD PRIMARY KEY (order_id);

-- order_items: composite key — one order can have multiple items, distinguished by position
ALTER TABLE raw.order_items ADD PRIMARY KEY (order_id, order_item_id);

-- order_payments: composite key — one order can have multiple payment installments
ALTER TABLE raw.order_payments ADD PRIMARY KEY (order_id, payment_sequential);

-- order_reviews: composite key — a single review can be attached to multiple orders
-- (Olist's review system propagates one buyer review across all their concurrent orders with that seller)
-- See data_quality.md finding DQ-001.
ALTER TABLE raw.order_reviews ADD PRIMARY KEY (review_id, order_id);

-- products: product_id is the catalog identifier
ALTER TABLE raw.products ADD PRIMARY KEY (product_id);

-- sellers: seller_id is the seller identifier
ALTER TABLE raw.sellers ADD PRIMARY KEY (seller_id);

-- product_category_name_translation: Portuguese name is the join key
ALTER TABLE raw.product_category_name_translation ADD PRIMARY KEY (product_category_name);

-- --- Foreign keys ---

-- Order ownership: every order belongs to a customer
ALTER TABLE raw.orders 
    ADD FOREIGN KEY (customer_id) REFERENCES raw.customers(customer_id);

-- Order items: every item belongs to an order, a product, and a seller
ALTER TABLE raw.order_items 
    ADD FOREIGN KEY (order_id) REFERENCES raw.orders(order_id);
ALTER TABLE raw.order_items 
    ADD FOREIGN KEY (product_id) REFERENCES raw.products(product_id);
ALTER TABLE raw.order_items 
    ADD FOREIGN KEY (seller_id) REFERENCES raw.sellers(seller_id);

-- Payments: every payment belongs to an order
ALTER TABLE raw.order_payments 
    ADD FOREIGN KEY (order_id) REFERENCES raw.orders(order_id);

-- Reviews: every review belongs to an order
ALTER TABLE raw.order_reviews 
    ADD FOREIGN KEY (order_id) REFERENCES raw.orders(order_id);


-- Product category translation: FK NOT enforced.
-- 623 product rows lack a matching translation (610 NULL category, 13 with missing English).
-- See data_quality.md finding DQ-002. Cleanup deferred to staging layer.
-- ALTER TABLE raw.products 
--     ADD FOREIGN KEY (product_category_name) REFERENCES raw.product_category_name_translation(product_category_name);