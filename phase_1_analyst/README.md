# Phase 1 — Analyst Foundations

This phase establishes the analytical and dimensional modeling foundation for the warehouse. The work spans 7 days and covers: raw data ingestion, constraint declaration, systematic profiling, cross-table analysis, business question feasibility verification, and star schema design.

The intended audience is anyone evaluating the engineering thinking behind the data model — recruiters, hiring managers, senior engineers, or future-me.

---

## What was done

| Day | Focus | Key deliverable |
|---|---|---|
| 1 | Environment setup | Repo, Postgres, venv, schemas |
| 2 | Raw data loading + constraints | `scripts/load_raw.py`, `sql/00_raw_constraints.sql`, DQ-001, DQ-002 |
| 3 | Per-table profiling | `notebooks/01_data_profiling.ipynb`, DQ-003 through DQ-018 |
| 4 | Outlier deep-dives + feasibility | `notebooks/02_cross_table_and_outliers.ipynb`, DQ-019, consolidated quality summary |
| 5 | Star schema conceptual design | (in conversation; consolidated in Day 6 artifacts) |
| 6 | Schema artifacts | `docs/star_schema_v1.png`, `docs/star_schema.dbml`, `docs/adr_001_star_schema.md`, `sql/01_star_schema.sql` |
| 7 | Polish and documentation | This README, `sql/README.md` |

---

## Folder structure

```text
phase_1_analyst/
├── data/                            # Olist CSVs (gitignored)
├── notebooks/
│   ├── 01_data_profiling.ipynb     # Per-table profiling for all 9 raw tables
│   └── 02_cross_table_and_outliers.ipynb  # Outlier dives + business question feasibility
├── scripts/
│   └── load_raw.py                 # Config-driven CSV → raw schema loader
├── sql/
│   ├── 00_raw_constraints.sql      # PKs and FKs on raw tables
│   ├── 01_star_schema.sql          # CREATE TABLE for marts layer (9 tables)
│   └── README.md                   # Planned Week 2 analytical queries
└── docs/
    ├── adr_001_star_schema.md      # Architecture decision record (11 decisions)
    ├── data_quality.md             # 19 documented findings + summary table
    ├── star_schema_v1.png          # Rendered schema diagram
    └── star_schema.dbml            # Diagram source (dbdiagram.io DSL)
```

---

## Setup and reproduction

To recreate this environment from scratch:

### 1. Prerequisites

- macOS or Linux (commands shown for macOS)
- PostgreSQL 14+ installed and running
- Python 3.11+
- ~5 GB free disk space (data + venv)

### 2. Clone and set up Python environment

```bash
git clone https://github.com/Rythm73/Ecommerce-Analytics-Pipeline.git
cd Ecommerce-Analytics-Pipeline

python3 -m venv venv
source venv/bin/activate
pip install -r requirements.txt
```

### 3. Set up the database

In Postgres:

```sql
CREATE DATABASE olist;
\c olist
CREATE SCHEMA raw;
CREATE SCHEMA staging;
CREATE SCHEMA marts;
```

### 4. Configure connection string

Create a `.env` file at the project root:
DATABASE_URL=postgresql://postgres:YOUR_PASSWORD@localhost:5432/olist
URL-encode any special characters in your password (e.g., `@` → `%40`).

### 5. Download the data

Download the Olist dataset from [Kaggle](https://www.kaggle.com/datasets/olistbr/brazilian-ecommerce) and place all 9 CSVs in `phase_1_analyst/data/`.

### 6. Run the pipeline

```bash
# Load raw data into raw schema
python phase_1_analyst/scripts/load_raw.py

# Apply PK / FK constraints (surfaces DQ-001 and DQ-002 findings)
psql -U postgres -h localhost -d olist -f phase_1_analyst/sql/00_raw_constraints.sql

# Create marts-layer tables (empty; will be populated in Phase 2)
psql -U postgres -h localhost -d olist -f phase_1_analyst/sql/01_star_schema.sql
```

**Note on re-runs:** the loader uses `if_exists="replace"`, which drops tables before recreating. Once constraints from `00_raw_constraints.sql` are applied, re-running the loader will fail because foreign keys depend on parent tables. To re-run from scratch:

```bash
psql -U postgres -h localhost -d olist -c "DROP SCHEMA raw CASCADE; CREATE SCHEMA raw;"
psql -U postgres -h localhost -d olist -c "DROP SCHEMA marts CASCADE; CREATE SCHEMA marts;"
python phase_1_analyst/scripts/load_raw.py
psql -U postgres -h localhost -d olist -f phase_1_analyst/sql/00_raw_constraints.sql
psql -U postgres -h localhost -d olist -f phase_1_analyst/sql/01_star_schema.sql
```

In Phase 2, this pipeline is replaced by idempotent dbt models that handle re-runs cleanly.

### 7. Run the notebooks

```bash
jupyter lab
```

Then open `phase_1_analyst/notebooks/` and run notebooks in order.

---

## Key artifacts (the things worth reading)

In rough order of interest for a technical reviewer:

1. **[Star schema ADR](docs/adr_001_star_schema.md)** — 11 documented design decisions with reasoning, alternatives, and consequences. The interview-relevant document.
2. **[Data quality findings](docs/data_quality.md)** — 19 findings with evidence and decisions. The "what could go wrong with this data" story.
3. **[Star schema diagram](docs/star_schema_v1.png)** — visual artifact of the model.
4. **[Profiling notebook](notebooks/01_data_profiling.ipynb)** — Day 3 work; per-table interrogation.
5. **[Cross-table notebook](notebooks/02_cross_table_and_outliers.ipynb)** — Day 4 work; outlier deep-dives and business question verification.
6. **[Marts DDL](sql/01_star_schema.sql)** — the actual CREATE TABLE statements implementing the ADR.

---

## What this phase deliberately doesn't include

- **Staging-layer transformations** — the `raw → staging` cleanups documented in `data_quality.md` are deferred to Phase 2 (dbt)
- **Marts population** — the 9 marts tables are created here but empty; populated in Phase 2
- **Analytical query implementations** — listed in [`sql/README.md`](sql/README.md) but written in Week 2
- **Dashboards / BI layer** — Phase 2

This boundary is deliberate. Phase 1's job is to *understand and model*. Phase 2's job is to *build the pipeline*. Mixing them is a common junior mistake that produces brittle schemas built around current quirks of the data.

---

## Database state after Phase 1

If you run the full pipeline above, your local Postgres will contain:

| Schema | Tables | Rows | Notes |
|---|---|---|---|
| `raw` | 9 | ~1.5M | Populated, with constraints applied |
| `staging` | 0 | 0 | Created but unused — Phase 2 populates this |
| `marts` | 9 | 0 | Tables created, awaiting Phase 2 population |