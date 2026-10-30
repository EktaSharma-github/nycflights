"""NYCFlights - analytics/build_notebook.py

Writes and executes nycflights_analysis.ipynb (+ .html) and saves the figures
in analytics/figures/. Run after run_all.ps1:

    .venv\\Scripts\\python analytics\\build_notebook.py
"""
import os
import subprocess
import sys

import nbformat as nbf

HERE = os.path.dirname(os.path.abspath(__file__))
NB = os.path.join(HERE, "nycflights_analysis.ipynb")
READINGS = os.path.join(HERE, "readings.md")

cells = []
md = lambda s: cells.append(nbf.v4.new_markdown_cell(s.strip()))
code = lambda s: cells.append(nbf.v4.new_code_cell(s.strip()))

md("""
# What makes a flight out of New York late?

Every query below runs in PostgreSQL against the `nycflights` schema; Python only
draws the charts and fits one small regression on the rows SQL returns.
Data: all 336,776 departures from JFK, LGA and EWR in 2013 (US DOT), with hourly
weather, aircraft and airport tables (R package *nycflights13*).
""")

code("""
import os
import numpy as np
import pandas as pd
import psycopg
import matplotlib.pyplot as plt

DSN = "host=localhost user=postgres password={} dbname=nycflights".format(os.environ.get("PGPASSWORD", "postgres"))
def q(sql):
    with psycopg.connect(DSN) as conn:
        conn.execute("SET search_path = nycflights")
        cur = conn.execute(sql)
        return pd.DataFrame(cur.fetchall(), columns=[d.name for d in cur.description])

BLUE, GRAY, INK, INK2 = "#2a78d6", "#b8b7b0", "#0b0b0b", "#52514e"
plt.rcParams.update({"figure.figsize": (8, 4.2), "figure.dpi": 110, "savefig.dpi": 160,
    "axes.spines.top": False, "axes.spines.right": False, "axes.edgecolor": "#d4d3cd",
    "axes.grid": True, "grid.color": "#ecebe6", "grid.linewidth": 0.8, "axes.axisbelow": True,
    "text.color": INK, "axes.labelcolor": INK2, "xtick.color": INK2, "ytick.color": INK2,
    "axes.titleweight": "bold", "axes.titlesize": 12, "axes.titlelocation": "left",
    "font.family": "DejaVu Sans"})
FIG = "figures"
os.makedirs(FIG, exist_ok=True)
def save(name):
    plt.tight_layout(); plt.savefig(f"{FIG}/{name}.png", bbox_inches="tight", facecolor="white"); plt.show()
""")

md("## 1. Time of day: delays snowball")
code("""
hour = q('''SELECT sched_dep_time/100 AS hour, COUNT(*) AS flights, AVG(dep_delay)::float AS avg_dep_delay
            FROM flight GROUP BY 1 HAVING COUNT(*) > 100 ORDER BY 1''')
fig, ax = plt.subplots()
ax.plot(hour.hour, hour.avg_dep_delay, color=BLUE, lw=2, marker="o", ms=5)
for h in (6, 19):
    v = hour.set_index("hour").avg_dep_delay[h]
    ax.annotate(f"{v:.1f} min", (h, v), textcoords="offset points", xytext=(0, 9), ha="center", color=INK)
ax.set_xticks(range(5, 24, 2)); ax.set_xlabel("Scheduled departure hour"); ax.set_ylabel("Average departure delay (min)")
ax.set_title("Average departure delay by scheduled hour, 2013")
save("01_delay_by_hour")
hour
""")

md("## 2. Airline: a 16-point spread in on-time rate")
code("""
card = q("SELECT carrier, airline, flights, on_time_pct::float, avg_arr_delay::float FROM v_carrier_scorecard WHERE flights >= 1000 ORDER BY on_time_pct")
fig, ax = plt.subplots(figsize=(8, 4.6))
ax.barh(card.airline, card.on_time_pct, color=BLUE, height=0.6)
for y, v in enumerate(card.on_time_pct):
    ax.text(v + 0.4, y, f"{v:.1f}%", va="center", color=INK, fontsize=9)
ax.set_xlim(0, 100); ax.grid(axis="y", visible=False)
ax.set_xlabel("Flights arriving within 15 minutes of schedule (%)")
ax.set_title("On-time rate by airline (airlines with 1,000+ flights)")
save("02_ontime_by_airline")
card
""")

md("## 3. Weather in the departure hour")
code("""
wx = q('''SELECT CASE WHEN w.visib_mi < 1 THEN 'Fog (<1 mi)' WHEN w.visib_mi < 5 THEN 'Haze (1-5 mi)' ELSE 'Clear (5+ mi)' END AS visibility,
                 CASE WHEN w.precip_in > 0 THEN 'Rain/snow' ELSE 'Dry' END AS precip,
                 COUNT(*) AS flights, AVG(f.dep_delay)::float AS avg_dep_delay
          FROM flight f JOIN weather w ON (w.origin, w.time_hour) = (f.origin, f.time_hour)
          GROUP BY 1, 2''')
order = ["Clear (5+ mi)", "Haze (1-5 mi)", "Fog (<1 mi)"]
p = wx.pivot(index="visibility", columns="precip", values="avg_dep_delay").loc[order]
x = np.arange(len(order)); w = 0.36
fig, ax = plt.subplots()
for i, (col, color) in enumerate([("Dry", GRAY), ("Rain/snow", BLUE)]):
    bars = ax.bar(x + (i - 0.5) * (w + 0.02), p[col], w, color=color, label=col)
    ax.bar_label(bars, fmt="%.0f", padding=3, color=INK, fontsize=9)
ax.set_xticks(x, order); ax.set_ylabel("Average departure delay (min)"); ax.grid(axis="x", visible=False)
ax.set_ylim(0, 42); ax.legend(frameon=False, loc="upper left", ncol=2); ax.set_title("Departure delay by visibility and precipitation")
save("03_weather")
wx.sort_values(["visibility", "precip"])
""")

md("## 4. Knock-on delays: the same plane, earlier that day")
code("""
legs = q('''SELECT dep_delay, LAG(arr_delay) OVER (PARTITION BY tailnum, flight_date ORDER BY sched_dep_time) AS prev_arr_delay
            FROM flight WHERE tailnum IS NOT NULL AND status <> 'Cancelled' ''').dropna()
legs = legs.astype(float)
bins = legs.assign(b=(legs.prev_arr_delay.clip(-30, 180) // 15) * 15).groupby("b").dep_delay.agg(["mean", "size"])
fig, ax = plt.subplots()
ax.plot(bins.index + 7.5, bins["mean"], color=BLUE, lw=2, marker="o", ms=5)
ax.axvline(15, color=GRAY, lw=1, ls="--"); ax.text(17, bins["mean"].max() * 0.95, "previous leg late (>15 min)", color=INK2, fontsize=9)
ax.set_xlabel("Previous NYC departure's arrival delay, same plane (min, 15-min bins, capped at 180)")
ax.set_ylabel("This departure's delay (min)")
ax.set_title("A late plane stays late")
save("04_knock_on")
print(f"pairs: {len(legs):,}   correlation r = {legs.corr().iloc[0, 1]:.3f}")
""")

md("""
## 5. Putting the suspects side by side

One ordinary least-squares regression of departure delay on the factors above.
Each row is a flight with a previous leg and a weather reading. Coefficients are in
minutes; for the 0/1 factors they read as *extra minutes of delay when the factor is present*.
""")
code("""
df = q('''WITH legs AS (
            SELECT f.*, LAG(f.arr_delay) OVER (PARTITION BY f.tailnum, f.flight_date ORDER BY f.sched_dep_time) AS prev_arr_delay
            FROM flight f WHERE f.tailnum IS NOT NULL AND f.status <> 'Cancelled')
          SELECT l.dep_delay, l.sched_dep_time/100 AS hour, l.prev_arr_delay,
                 (w.precip_in > 0)::int AS rain, (w.visib_mi < 1)::int AS fog,
                 (EXTRACT(MONTH FROM l.flight_date) IN (6,7,12))::int AS peak_month,
                 (l.carrier IN ('EV','FL','MQ','9E'))::int AS regional_low_cost
          FROM legs l JOIN weather w ON (w.origin, w.time_hour) = (l.origin, l.time_hour)
          WHERE l.prev_arr_delay IS NOT NULL''').astype(float)
X = df.drop(columns="dep_delay")
X["prev_late_min"] = X.pop("prev_arr_delay").clip(lower=0)
A = np.column_stack([np.ones(len(X)), X.values])
beta, *_ = np.linalg.lstsq(A, df.dep_delay.values, rcond=None)
resid = df.dep_delay.values - A @ beta
r2 = 1 - resid.var() / df.dep_delay.var()
se = np.sqrt(np.diag(resid.var() * np.linalg.inv(A.T @ A)))
coef = pd.DataFrame({"coef_min": beta, "std_err": se, "t": beta / se}, index=["intercept"] + list(X.columns)).round(3)
print(f"n = {len(df):,} flights   R^2 = {r2:.3f}")
coef
""")

md("## Readings")

nb = nbf.v4.new_notebook(cells=cells, metadata={"kernelspec": {"name": "nycflights", "display_name": "NYCFlights", "language": "python"}})
if os.path.exists(READINGS):
    nb.cells.append(nbf.v4.new_markdown_cell(open(READINGS, encoding="utf-8").read()))
nbf.write(nb, NB)

subprocess.run([sys.executable, "-m", "jupyter", "nbconvert", "--to", "notebook", "--execute", "--inplace",
                "--ExecutePreprocessor.kernel_name=nycflights", NB], cwd=HERE, check=True)
subprocess.run([sys.executable, "-m", "jupyter", "nbconvert", "--to", "html", NB], cwd=HERE, check=True)
print("wrote", NB)
