---
# Olist Retail Analytics Pipeline

End-to-end data engineering project building a retail analytics platform on Brazilian e-commerce data (Olist, 2016–2018). The project is structured in two phases that mirror how data engineering work happens in industry: first you understand and model the data, then you build production infrastructure on top of it.

---

## Project structure
ecommerce-analytics-pipeline/
├── phase_1_analyst/    ← analytical foundations: loading, profiling, modeling
│   ├── data/           (gitignored — Olist CSVs)
│   ├── notebooks/      (profiling + cross-table analysis)
│   ├── scripts/        (loader)
│   ├── sql/            (constraints + star schema DDL)
│   └── docs/           (data quality findings, ADR, schema diagram)
├── phase_2_engineer/   ← production infra (Snowflake, dbt) — Week 4
└── README.md

## Current status

**Phase 1 complete.** Phase 2 begins Week 2.

### Phase 1 accomplishments

- **9 raw tables loaded** (~1.5M rows) from Olist's Kaggle dataset into local Postgres, with explicit dtypes and date parsing
- **8 primary keys + 6 foreign keys** declared as data quality constraints; failures surfaced as findings
- **19 documented data quality findings** ([data_quality.md](phase_1_analyst/docs/data_quality.md)), each with evidence, decision, and downstream implication
- **5 business questions verified feasible** against raw data with documented quality cleanups (see `notebooks/02_cross_table_and_outliers.ipynb`)
- **Star schema designed**: 4 fact tables, 5 dimension tables. Diagram: [star_schema_v1.png](phase_1_analyst/docs/star_schema_v1.png). Design rationale: [adr_001_star_schema.md](phase_1_analyst/docs/adr_001_star_schema.md)
- **Marts DDL created**: 9 empty tables ready for Phase 2 population

### Headline insights surfaced

- **21-day "patience cliff"**: average review score drops from 4.42 (0–7 day delivery) to 2.26 (31–60 day delivery); 1-star rate spikes from 5% to 54%. Late delivery is the dominant negative driver of customer satisfaction.
- **3.4% repeat-buyer rate** — Olist has a weak retention story; cohort analysis triangles will be sparse.
- **Top 3 revenue categories**: health_beauty (R$1.44M), watches_gifts (R$1.31M), bed_bath_table (R$1.24M).
- **Worst-performing sellers identified**: `1ca7077d...` (114 orders, 2.20 avg score, 59% 1-star).
- **97% fulfillment success rate**; geographic supply concentrated in São Paulo (60% of sellers vs 42% of buyers).

---

## What's coming in Phase 2

- Migrate raw → staging → marts pipeline to **dbt** with version-controlled, testable transformations
- Move the warehouse from local Postgres to **Snowflake**
- Implement the staging-layer cleanups documented in [data_quality.md](phase_1_analyst/docs/data_quality.md)
- Build the 8 analytical queries (one per business question) plus dashboards
- Add data quality tests via dbt's `tests/` directory

---

## Where to start as a reviewer

If you have 5 minutes:
1. Read [phase_1_analyst/docs/adr_001_star_schema.md](phase_1_analyst/docs/adr_001_star_schema.md) — the architecture decisions and reasoning
2. Skim the summary table at the top of [data_quality.md](phase_1_analyst/docs/data_quality.md) — 19 findings classified by severity and fix layer
3. Open [star_schema_v1.png](phase_1_analyst/docs/star_schema_v1.png) — the model diagram

If you have more time:
- The two Jupyter notebooks tell the discovery story end-to-end
- The SQL files (`phase_1_analyst/sql/`) show constraint declaration and DDL conventions
- The Phase 1 README ([phase_1_analyst/README.md](phase_1_analyst/README.md)) has full setup and reproduction instructions

---

## Tech stack

**Phase 1:** Python (pandas, SQLAlchemy), PostgreSQL 18, JupyterLab, dbdiagram.io

**Phase 2 (planned):** Snowflake, dbt, Airflow/Dagster (TBD), GitHub Actions for CI