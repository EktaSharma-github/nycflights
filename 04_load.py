"""NYCFlights - 04_load.py

Loads the five nycflights13 CSVs in data/ into the 7-table schema, in one
transaction. Run after 02_ddl.sql and 03_logic.sql:

    .venv\\Scripts\\python 04_load.py

Cleaning decisions (see 01_design.md section 5):
  D1  4 destination codes (BQN, PSE, SJU, STT) are missing from airports.csv
      -> placeholder airport rows with in_source = FALSE.
  D2  721 tail numbers flown are missing from planes.csv (mostly MQ and AA)
      -> placeholder plane rows with in_source = FALSE.
  D3  3 airports have no tzone; each has a UTC offset that maps to exactly one
      tzone in the file (-5 -> America/New_York, -9 -> America/Anchorage).
  D4  2 routes (EWR-EGE, JFK-EGE) have two distances 1 mile apart
      -> the route keeps the more common distance.
"""
import os
import time

import pandas as pd
import psycopg

DATA = os.path.join(os.path.dirname(os.path.abspath(__file__)), "data")
DSN = "host=localhost user=postgres password={} dbname={}".format(
    os.environ.get("PGPASSWORD", "postgres"), os.environ.get("NYCF_DB", "nycflights"))


def read(name, **kw):
    return pd.read_csv(os.path.join(DATA, name + ".csv"), **kw)


def copy(cur, table, df):
    """COPY a DataFrame into a table; NaN becomes NULL."""
    df = df.copy()
    for c in df.select_dtypes("float").columns:     # concat/NaN turned ints into floats
        if (df[c].dropna() % 1 == 0).all():
            df[c] = df[c].astype("Int64")
    cols = ", ".join(df.columns)
    rows = df.astype(object).where(df.notna(), None).itertuples(index=False, name=None)
    with cur.copy(f"COPY {table} ({cols}) FROM STDIN") as cp:
        for row in rows:
            cp.write_row(row)
    print(f"  {table:<9} {len(df):>8,} rows")


def main():
    t0 = time.time()
    # keep_default_na=False stops pandas from reading codes like "NAN" as missing
    airports = read("airports", keep_default_na=False, na_values=["NA", ""])
    airlines = read("airlines")
    planes = read("planes")
    weather = read("weather")
    flights = read("flights")

    # timezone: tzone -> utc_offset holds for every tzone in the file
    tz = airports.dropna(subset=["tzone"]).groupby("tzone").tz.agg(["min", "max"])
    assert (tz["min"] == tz["max"]).all(), "tzone -> tz does not hold"
    timezone = tz["min"].rename("utc_offset").reset_index()

    # D3: fill a missing tzone when the offset maps to a single tzone
    by_offset = timezone.groupby("utc_offset").tzone.agg(list)
    unique_offset = {o: z[0] for o, z in by_offset.items() if len(z) == 1}
    missing = airports.tzone.isna()
    airports.loc[missing, "tzone"] = airports.loc[missing, "tz"].map(unique_offset)
    print(f"D3 filled tzone for {missing.sum()} airports")

    # D1: placeholder airports
    codes = set(flights.origin) | set(flights.dest)
    extra = sorted(codes - set(airports.faa))
    airport = airports.rename(columns={"alt": "alt_ft"})[
        ["faa", "name", "lat", "lon", "alt_ft", "dst", "tzone"]].assign(in_source=True)
    airport = pd.concat([airport, pd.DataFrame({"faa": extra, "in_source": False})])
    print(f"D1 placeholder airports: {', '.join(extra)}")

    # D2: placeholder planes
    plane = planes.rename(columns={"year": "year_built"}).assign(in_source=True)
    extra_tail = sorted(set(flights.tailnum.dropna()) - set(plane.tailnum))
    plane = pd.concat([plane, pd.DataFrame({"tailnum": extra_tail, "in_source": False})])
    print(f"D2 placeholder planes: {len(extra_tail)}")

    # D4: one distance per route (the most common one)
    route = (flights.groupby(["origin", "dest", "distance"]).size().rename("n").reset_index()
             .sort_values(["origin", "dest", "n"], ascending=[True, True, False])
             .drop_duplicates(["origin", "dest"])
             .rename(columns={"distance": "distance_mi"})[["origin", "dest", "distance_mi"]])
    changed = flights.merge(route, on=["origin", "dest"]).query("distance != distance_mi")
    print(f"D4 routes: {len(route)}, flights whose distance was harmonised: {len(changed)}")

    weather = weather.rename(columns={"temp": "temp_f", "dewp": "dewp_f", "precip": "precip_in",
                                      "pressure": "pressure_mb", "visib": "visib_mi"})
    weather = weather[["origin", "time_hour", "temp_f", "dewp_f", "humid", "wind_dir", "wind_speed",
                       "wind_gust", "precip_in", "pressure_mb", "visib_mi"]]

    flights["flight_date"] = pd.to_datetime(flights[["year", "month", "day"]]).dt.date
    flight = flights.rename(columns={"flight": "flight_no"})[
        ["flight_date", "carrier", "flight_no", "tailnum", "origin", "dest", "sched_dep_time",
         "dep_time", "dep_delay", "sched_arr_time", "arr_time", "arr_delay", "air_time", "time_hour"]]
    for c in ["dep_time", "dep_delay", "arr_time", "arr_delay", "air_time"]:
        flight[c] = flight[c].astype("Int64")

    print("Loading ...")
    with psycopg.connect(DSN) as conn, conn.cursor() as cur:
        cur.execute("SET search_path = nycflights")
        copy(cur, "timezone", timezone)
        copy(cur, "airport", airport)
        copy(cur, "airline", airlines)
        copy(cur, "plane", plane)
        copy(cur, "route", route)
        copy(cur, "weather", weather)
        copy(cur, "flight", flight)          # trg_flight_status fills status
        cur.execute("ANALYZE")
        cur.execute("SELECT status, COUNT(*) FROM flight GROUP BY 1 ORDER BY 2 DESC")
        print("  status:", ", ".join(f"{s} {n:,}" for s, n in cur.fetchall()))
    print(f"Done in {time.time() - t0:.0f} s")


if __name__ == "__main__":
    main()
