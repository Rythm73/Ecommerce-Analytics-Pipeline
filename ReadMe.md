# Olist Retail Analytics Pipeline

End-to-end data engineering project building a retail analytics platform on Brazilian e-commerce data from the Olist dataset (2016–2018).

This project is structured in two phases to mirror real-world data engineering workflows:

1. **Phase 1 — Analyst Foundations**
   - Data loading
   - Data profiling
   - Data quality assessment
   - Dimensional modeling

2. **Phase 2 — Production Engineering**
   - Scalable transformation pipelines
   - Cloud warehouse infrastructure
   - Automated testing and orchestration

---

# Project Structure

```text
ecommerce-analytics-pipeline/
│
├── phase_1_analyst/          # Analytical foundations
│   ├── data/                 # Olist CSV files (gitignored)
│   ├── notebooks/            # Profiling and exploratory analysis
│   ├── scripts/              # Data loading scripts
│   ├── sql/                  # Constraints and star schema DDL
│   └── docs/                 # Data quality reports, ADRs, diagrams
│
├── phase_2_engineer/         # Production pipeline infrastructure
│
└── README.md
```

---

# Current Status

## ✅ Phase 1 Complete

Phase 1 established the analytical and dimensional modeling foundation for the warehouse.

### Phase 1 Accomplishments

- Loaded **9 raw tables** (~1.5M rows) from the Olist Kaggle dataset into PostgreSQL with explicit dtypes and date parsing
- Declared **8 primary keys** and **6 foreign keys** as integrity constraints to surface data quality issues early
- Documented **19 data quality findings** with:
  - evidence
  - remediation decisions
  - downstream analytical implications
- Verified feasibility for **5 business questions** through cross-table analysis and outlier validation
- Designed a **star schema** consisting of:
  - 4 fact tables
  - 5 dimension tables
- Created marts-layer DDL scripts for all warehouse tables
- Documented architecture decisions and modeling rationale using ADRs

---

# Key Insights Identified

## Delivery Delays Strongly Impact Customer Satisfaction

A clear **21-day “patience cliff”** was identified:

| Delivery Delay | Avg Review Score | 1-Star Review Rate |
|---|---|---|
| 0–7 days | 4.42 | 5% |
| 31–60 days | 2.26 | 54% |

Late delivery appears to be the dominant driver of negative customer reviews.

---

## Weak Customer Retention

- Repeat buyer rate is only **3.4%**
- Cohort retention analysis is expected to produce sparse retention curves

---

## Top Revenue Categories

| Category | Revenue |
|---|---|
| health_beauty | R$1.44M |
| watches_gifts | R$1.31M |
| bed_bath_table | R$1.24M |

---

## Seller Performance Outliers

Example poorly performing seller:

- Seller `1ca7077d...`
  - 114 orders
  - 2.20 average review score
  - 59% 1-star review rate

---

## Marketplace Fulfillment Trends

- Overall fulfillment success rate: **97%**
- Seller geography is heavily concentrated in São Paulo:
  - 60% of sellers
  - 42% of buyers

---

# Phase 2 Roadmap

Phase 2 focuses on production-grade analytics engineering.

## Planned Work

- Migrate transformations to a **dbt** workflow:
  - raw → staging → marts
- Move the warehouse from PostgreSQL to **Snowflake**
- Implement staging-layer cleanups documented in `data_quality.md`
- Build analytical marts and dashboard-ready queries
- Add automated data quality tests using dbt
- Introduce orchestration:
  - Airflow or Dagster (TBD)
- Add CI/CD with GitHub Actions

---

# Reviewer Guide

## If You Have 5 Minutes

Start with:

1. `phase_1_analyst/docs/adr_001_star_schema.md`
   - Architecture decisions and modeling rationale

2. `phase_1_analyst/docs/data_quality.md`
   - Summary of all 19 data quality findings

3. `phase_1_analyst/docs/star_schema_v1.png`
   - Star schema diagram

---

## If You Have More Time

Explore:

- Jupyter notebooks for the complete analytical workflow
- SQL DDL and constraint scripts
- Phase 1 setup and reproducibility instructions

---

# Tech Stack

## Phase 1

- Python
  - pandas
  - SQLAlchemy
- PostgreSQL
- JupyterLab
- dbdiagram.io

---

## Phase 2 (Planned)

- Snowflake
- dbt
- Airflow or Dagster
- GitHub Actions

---

# Dataset

Dataset: **Olist Brazilian E-Commerce Dataset (Kaggle)**

The dataset contains:
- Orders
- Customers
- Sellers
- Products
- Payments
- Reviews
- Delivery events
- Geolocation data

Time range:
- 2016–2018

---

# Future Enhancements

Potential future additions:

- Incremental dbt models
- Slowly changing dimensions (SCDs)
- Snapshotting
- ML-based delivery delay prediction
- Customer segmentation pipelines
- Real-time ingestion simulation
- Snowflake cost optimization analysis
