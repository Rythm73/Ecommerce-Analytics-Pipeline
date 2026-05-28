# Olist Brazil E-commerce: Operational & Customer Insights

> End-to-end data analyst project on Olist Brazil e-commerce data (2016–2018). PostgreSQL 18 for warehousing, Python 3.13 with pandas and SQLAlchemy for profiling, SQL for analytical aggregation, Tableau Public for visualization.

**📊 [Live Tableau Dashboard →](https://public.tableau.com/app/profile/gowthami.ratikrinda/viz/Book1_17798966064910/Dashboard1)**

---

## Headline finding: the 21-day patience cliff

Customer review scores remain stable for delivery times under 21 days, then collapse sharply.

| Delivery time | Orders | Avg score | % 1-star | % 5-star |
|---|---:|---:|---:|---:|
| 0–7 days | 30,550 | 4.41 | 5.4% | 68.2% |
| 8–14 days | 37,775 | 4.30 | 6.6% | 62.5% |
| 15–21 days | 16,054 | 4.12 | 8.8% | 54.8% |
| **22–30 days** | **7,265** | **3.55** | **20.0%** | **39.3%** |
| 31–60 days | 3,897 | 2.21 | 55.6% | 15.8% |
| 60+ days | 283 | 2.16 | 60.4% | 15.9% |

**Operational implication:** rather than generic "improve delivery," focus on the 12% of orders that breach the 21-day threshold. They drive the majority of 1-star reviews.

## Project context

Olist is a Brazilian e-commerce marketplace connecting small sellers to large retail platforms. With ~1.5M rows of order, customer, seller, payment, and review data across 9 raw tables, the dataset offers a realistic environment for the operational questions a marketplace analyst would actually face.

This project investigates five questions:

1. **What categories drive revenue?** (Pricing and inventory strategy)
2. **How does delivery time affect customer satisfaction?** (Operational priorities)
3. **Are some sellers dragging down marketplace reputation?** (Quality control)
4. **Where geographically is the business strongest, and where could it grow?** (Expansion strategy)
5. **Where do orders drop off in the fulfillment pipeline?** (Process bottlenecks)

The analysis covers data from September 2016 through August 2018.

## Tech stack

| Layer | Tool |
|---|---|
| Database | PostgreSQL |
| Language | Python (pandas, SQLAlchemy), SQL |
| Visualization | Tableau Public |

## Other key insights

### Revenue is geographically concentrated

São Paulo (R$5.2M), Rio de Janeiro, and Minas Gerais together account for ~60% of total marketplace revenue. The Amazon-region states (RR, AP, AM, PA) combined contribute under 2%. The customer base is similarly concentrated: 42% of customers are in SP alone. This suggests Olist's growth ceiling in the southeast and untapped opportunity in the north.

### A small number of sellers drag down satisfaction

Of ~1,500 sellers with 10+ orders, fewer than 50 fall below an average review score of 3.0. But these underperformers handle real volume — the worst-rated seller in the dataset processed 114 orders at an average score of 2.20 (58.8% 1-star reviews). Marketplace-wide reputation risk is concentrated in a small, identifiable group.

### Fulfillment is efficient; the data has rough edges

97% of orders reach `delivered` status. Only ~1.2% exit the pipeline via `canceled` or `unavailable`. However, investigation surfaced semantic issues in the order lifecycle data: 64 orders with administrative bulk-closure delivery dates (DQ-019), 23 orders with carrier timestamps after customer delivery (clock skew, DQ-006), and `order_approved_at` actually capturing payment settlement rather than approval (DQ-005). All documented in `docs/data_quality.md`.

## Business recommendations

### 1. Treat 21+ day delivery times as a customer experience emergency

The 21-day patience cliff is the single most actionable finding in this dataset. 12% of orders breach this threshold, and they generate the majority of 1-star reviews. Rather than pursuing generic "faster shipping" initiatives, Olist should:

- **Build an early-warning system** that flags orders projected to exceed 21 days, based on carrier handoff timing
- **Proactively communicate** with customers whose orders cross the threshold (transparent delay notifications correlate with higher recovery)
- **Track the 21-day breach rate** as a top-level operational KPI alongside delivery time itself

### 2. Audit and act on bottom-decile sellers

Fewer than 50 sellers fall below 3.0 stars on review — a small enough group to investigate individually. Recommended workflow:

- **Quarterly seller scorecard**: surface the bottom 50 by review score (filtered to sellers with 10+ orders)
- **Two-strike policy**: sellers below 3.0 stars for two consecutive quarters receive intervention (training, account review, or suspension)
- **Quality-weighted ranking** in search results: down-rank consistently low-rated sellers in default product listings to protect new buyers

### 3. Investigate growth potential in the underserved north

Northern Brazilian states contribute under 2% of revenue but represent ~30% of the country's geographic area and significant population. Three angles worth investigating:

- **Logistics partnerships** with regional carriers to reduce delivery times to Amazon-region states (likely the binding constraint)
- **Seller acquisition** in northern capital cities (Belém, Manaus) to reduce shipping distances
- **Local payment methods**: investigate whether `boleto` adoption differs by region and whether that affects conversion.

## Next steps and limitations

### Limitations of this analysis

- **Static snapshot.** The dataset covers Sept 2016 – Aug 2018. Findings reflect that period; consumer behavior and Olist's marketplace have likely shifted since.
- **Review attribution is imperfect.** When an order has items from multiple sellers, the order's review is attributed to all of them. The data doesn't tell us which seller a complaint was actually about, so seller-level review metrics carry some noise.
- **Cohort analysis was deprioritized.** Olist's 3.4% repeat-buyer rate is too low for meaningful cohort retention work on this dataset; that analysis was skipped in favor of operational insights.
- **No causal claims.** Correlations between delivery time and review scores are strong, but this is observational data — confounders like seller reliability and product category likely matter.

### What I'd do with more time

- **Geographic deep-dive into the patience cliff.** Does the 21-day threshold hold uniformly across Brazilian states, or is it driven by long-tail northern deliveries? A state-level breakdown of the delivery-vs-review curve would refine the operational recommendation.
- **Seller cohort analysis.** Group sellers by tenure on the platform and see whether new sellers cluster in the underperformer group (training opportunity) or whether the bad sellers are long-tenured (intervention opportunity).
- **Category-level review patterns.** Are some categories systematically more 1-star-prone (e.g., furniture due to delivery damage)? This would refine the seller intervention logic.
- **Build the production data pipeline.** The dimensional model in `sql/01_star_schema.sql` was designed but not populated. A natural extension is to implement it via dbt and Snowflake for repeatable analytical workflows.