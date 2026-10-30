-- NYCFlights — 05_queries.sql
-- Research question: what makes a flight out of New York late?
-- Each query looks at one suspect: airline, time of day, season, weather,
-- plane age, route, the previous flight, and time made up in the air.
SET search_path = nycflights;
\pset footer off

\echo '== Q1  Airline scorecard (view v_carrier_scorecard)'
SELECT RANK() OVER (ORDER BY on_time_pct DESC) AS rank, *
FROM v_carrier_scorecard
WHERE flights >= 1000
ORDER BY rank;

\echo '== Q2  Delays build up through the day'
SELECT sched_dep_time / 100                                            AS hour,
       COUNT(*)                                                        AS flights,
       ROUND(AVG(dep_delay), 1)                                        AS avg_dep_delay,
       ROUND(100.0 * COUNT(*) FILTER (WHERE status = 'Delayed') / COUNT(*), 1) AS delayed_pct
FROM flight
GROUP BY 1
HAVING COUNT(*) > 100
ORDER BY 1;

\echo '== Q3  Season: delays and cancellations by month'
SELECT TO_CHAR(flight_date, 'MM Mon')                                     AS month,
       COUNT(*)                                                           AS flights,
       ROUND(AVG(arr_delay), 1)                                           AS avg_arr_delay,
       ROUND(100.0 * COUNT(*) FILTER (WHERE status = 'Cancelled') / COUNT(*), 2) AS cancelled_pct
FROM flight
GROUP BY 1
ORDER BY 1;

\echo '== Q4  Weather at the origin airport in the departure hour'
SELECT CASE WHEN w.visib_mi < 1  THEN '1 fog (<1 mi)'
            WHEN w.visib_mi < 5  THEN '2 haze (1-5 mi)'
            ELSE                      '3 clear (5+ mi)' END                 AS visibility,
       CASE WHEN w.precip_in > 0 THEN 'rain/snow' ELSE 'dry' END           AS precip,
       COUNT(*)                                                           AS flights,
       ROUND(AVG(f.dep_delay), 1)                                         AS avg_dep_delay,
       ROUND(100.0 * COUNT(*) FILTER (WHERE f.status = 'Cancelled') / COUNT(*), 1) AS cancelled_pct
FROM flight f
JOIN weather w ON (w.origin, w.time_hour) = (f.origin, f.time_hour)
GROUP BY 1, 2
ORDER BY 1, 2;

\echo '== Q5  Plane age (only planes present in planes.csv)'
SELECT CASE WHEN 2013 - p.year_built < 5  THEN '0-4'
            WHEN 2013 - p.year_built < 10 THEN '5-9'
            WHEN 2013 - p.year_built < 15 THEN '10-14'
            WHEN 2013 - p.year_built < 20 THEN '15-19'
            ELSE                               '20+' END       AS age_years,
       COUNT(*)                                                AS flights,
       ROUND(AVG(f.arr_delay), 1)                              AS avg_arr_delay
FROM flight f
JOIN plane p USING (tailnum)
WHERE p.in_source AND p.year_built IS NOT NULL
GROUP BY 1
ORDER BY MIN(2013 - p.year_built);

\echo '== Q6  Ten most delayed routes (365+ flights a year)'
SELECT * FROM (
    SELECT f.origin, f.dest, a.name AS destination, r.distance_mi,
           COUNT(*)                         AS flights,
           ROUND(AVG(f.arr_delay), 1)       AS avg_arr_delay,
           RANK() OVER (ORDER BY AVG(f.arr_delay) DESC) AS rank
    FROM flight f
    JOIN route   r ON (r.origin, r.dest) = (f.origin, f.dest)
    JOIN airport a ON a.faa = f.dest
    GROUP BY f.origin, f.dest, a.name, r.distance_mi
    HAVING COUNT(*) >= 365
) t
WHERE rank <= 10
ORDER BY rank;

-- The data holds NYC departures only, so the "previous leg" is the same plane's
-- previous NYC departure that day; its delay reaches us via the unseen return flight.
\echo '== Q7  Knock-on delays: same plane, previous NYC departure that day'
WITH legs AS (
    SELECT tailnum, flight_date, dep_delay,
           LAG(arr_delay) OVER (PARTITION BY tailnum, flight_date
                                ORDER BY sched_dep_time) AS prev_arr_delay
    FROM flight
    WHERE tailnum IS NOT NULL AND status <> 'Cancelled'
)
SELECT CASE WHEN prev_arr_delay <= 15 THEN '1 prev on time'
            WHEN prev_arr_delay <= 60 THEN '2 prev 16-60 min late'
            ELSE                           '3 prev 60+ min late' END AS previous_leg,
       COUNT(*)                                                   AS flights,
       ROUND(AVG(dep_delay), 1)                                   AS avg_dep_delay
FROM legs
WHERE prev_arr_delay IS NOT NULL
GROUP BY 1
ORDER BY 1;

\echo '== Q7b Correlation between previous arrival delay and this departure delay'
SELECT ROUND(CORR(prev_arr_delay, dep_delay)::numeric, 3) AS r
FROM (SELECT dep_delay,
             LAG(arr_delay) OVER (PARTITION BY tailnum, flight_date ORDER BY sched_dep_time) AS prev_arr_delay
      FROM flight WHERE tailnum IS NOT NULL AND status <> 'Cancelled') t;

\echo '== Q8  Do pilots make up time in the air? (minutes gained = dep_delay - arr_delay)'
SELECT CASE WHEN r.distance_mi < 500  THEN '1 short (<500 mi)'
            WHEN r.distance_mi < 1500 THEN '2 medium (500-1500)'
            ELSE                           '3 long (1500+)' END   AS haul,
       COUNT(*)                                                    AS flights,
       ROUND(AVG(f.dep_delay - f.arr_delay) FILTER (WHERE f.dep_delay > 15), 1) AS gained_when_late,
       ROUND(AVG(f.dep_delay - f.arr_delay), 1)                    AS gained_all
FROM flight f
JOIN route r ON (r.origin, r.dest) = (f.origin, f.dest)
WHERE f.arr_delay IS NOT NULL
GROUP BY 1
ORDER BY 1;
