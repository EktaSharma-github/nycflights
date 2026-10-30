# NYCFlights — what makes a flight out of New York late?

A PostgreSQL case study for the FDS/DBMS course (PGDBA Batch 12). It uses all 336,776 flights that left JFK, LGA and EWR in 2013 (US DOT data, from the *nycflights13* dataset), loaded into 7 tables in BCNF.

| File | What it holds |
|---|---|
| `01_design.md` | ER model, schema, FDs tested in SQL, BCNF decisions, data issues, presentation split |
| `02_ddl.sql` | 7 tables, keys and 20 CHECK constraints |
| `03_logic.sql` | status trigger, 2 views, `carrier_report(month)` |
| `04_load.py` | cleans the CSVs in `data/` and loads them with COPY (~80 s) |
| `05_queries.sql` | Q1–Q8, one query per suspect: airline, hour, month, weather, plane age, route, knock-on delays, time made up in the air |
| `06_demo.sql` | live demo (index, trigger, constraints), rolled back at the end |
| `analytics/` | notebook, figures and readings |
| `results/` | psql output of 05 and 06 |

## Run

Requirements: PostgreSQL 18 on localhost (user `postgres`) and Python 3.12.

```powershell
python -m venv .venv
.venv\Scripts\pip install nycflights13 pandas "psycopg[binary]" matplotlib jupyter nbconvert ipykernel
.venv\Scripts\python -m ipykernel install --user --name nycflights
powershell -ExecutionPolicy Bypass -File run_all.ps1       # database, load, queries and demo
.venv\Scripts\python analytics\build_notebook.py            # notebook and figures
```

## Findings

| Factor | Effect |
|---|---|
| Plane's previous NYC departure that day | strongest: a departure leaves 84 min late on average after a previous leg 60+ min late (r = 0.375) |
| Time of day | average delay grows from 1.6 min at 6 am to 24.8 min at 7 pm |
| Weather | rain or snow on a clear day raises the average delay from 11 to 33 min |
| Airline | on-time rates differ by 16.5 points |
| Plane age | no clear effect |

A regression with all factors together explains 18% of the variation in delay (R² = 0.18).
