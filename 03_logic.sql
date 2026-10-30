-- NYCFlights — 03_logic.sql
-- Trigger, views and one function. Run after 02_ddl.sql and before 04_load.py
-- (the loader relies on the trigger to fill flight.status).
SET search_path = nycflights;

-- ---------------------------------------------------------------------------
-- Trigger: derive status from the times, so it can never disagree with them.
-- "Delayed" uses the US DOT rule: arrival more than 15 minutes late.
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION set_flight_status() RETURNS trigger AS $$
BEGIN
    NEW.status := CASE
        WHEN NEW.dep_time IS NULL   THEN 'Cancelled'
        WHEN NEW.arr_delay IS NULL  THEN 'Diverted'
        WHEN NEW.arr_delay > 15     THEN 'Delayed'
        ELSE                             'On time'
    END;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_flight_status
    BEFORE INSERT OR UPDATE OF dep_time, arr_delay ON flight
    FOR EACH ROW EXECUTE FUNCTION set_flight_status();

-- ---------------------------------------------------------------------------
-- View 1: one wide row per flight, the starting point for most analysis.
-- ---------------------------------------------------------------------------
CREATE OR REPLACE VIEW v_flight_detail AS
SELECT f.flight_id,
       f.flight_date,
       EXTRACT(MONTH FROM f.flight_date)::int   AS month,
       EXTRACT(ISODOW FROM f.flight_date)::int  AS weekday,      -- 1 = Monday
       f.sched_dep_time / 100                   AS sched_hour,
       f.carrier,
       al.name                                  AS airline,
       f.origin, f.dest, r.distance_mi,
       f.tailnum,
       2013 - p.year_built                      AS plane_age,
       f.dep_delay, f.arr_delay, f.status,
       w.temp_f, w.wind_speed, w.precip_in, w.visib_mi
FROM flight f
JOIN airline al ON al.carrier = f.carrier
JOIN route   r  ON (r.origin, r.dest) = (f.origin, f.dest)
LEFT JOIN plane   p ON p.tailnum = f.tailnum
LEFT JOIN weather w ON (w.origin, w.time_hour) = (f.origin, f.time_hour);

-- ---------------------------------------------------------------------------
-- View 2: the airline scorecard.
-- ---------------------------------------------------------------------------
CREATE OR REPLACE VIEW v_carrier_scorecard AS
SELECT f.carrier,
       al.name                                                         AS airline,
       COUNT(*)                                                        AS flights,
       ROUND(100.0 * COUNT(*) FILTER (WHERE status = 'On time')   / COUNT(*), 1) AS on_time_pct,
       ROUND(100.0 * COUNT(*) FILTER (WHERE status = 'Cancelled') / COUNT(*), 1) AS cancelled_pct,
       ROUND(AVG(arr_delay), 1)                                        AS avg_arr_delay
FROM flight f
JOIN airline al USING (carrier)
GROUP BY f.carrier, al.name;

-- ---------------------------------------------------------------------------
-- Function: scorecard for one month, e.g. SELECT * FROM carrier_report(7);
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION carrier_report(p_month int)
RETURNS TABLE (carrier char(2), flights bigint, on_time_pct numeric, avg_arr_delay numeric) AS $$
    SELECT f.carrier,
           COUNT(*),
           ROUND(100.0 * COUNT(*) FILTER (WHERE f.status = 'On time') / COUNT(*), 1),
           ROUND(AVG(f.arr_delay), 1)
    FROM nycflights.flight f
    WHERE EXTRACT(MONTH FROM f.flight_date) = p_month
    GROUP BY f.carrier
    ORDER BY 3 DESC;
$$ LANGUAGE sql STABLE;
