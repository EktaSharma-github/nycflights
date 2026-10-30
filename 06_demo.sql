-- NYCFlights — 06_demo.sql
-- Live demo for the presentation. Everything runs inside a transaction that is
-- rolled back, so the database is unchanged afterwards and the demo can be rerun.
SET search_path = nycflights;
\pset footer off

BEGIN;

\echo '== D1  Index: find every flight flown by one plane'
\echo '-- before: no index on tailnum, so PostgreSQL reads all 336,776 rows'
EXPLAIN (ANALYZE, TIMING OFF, COSTS OFF, SUMMARY OFF)
SELECT * FROM flight WHERE tailnum = 'N725MQ';

CREATE INDEX idx_flight_tailnum ON flight (tailnum);
ANALYZE flight;

\echo '-- after: the index jumps straight to the matching rows'
EXPLAIN (ANALYZE, TIMING OFF, COSTS OFF, SUMMARY OFF)
SELECT * FROM flight WHERE tailnum = 'N725MQ';

\echo '== D2  Trigger: cancel a flight and the status follows'
SELECT flight_id, flight_date, carrier, flight_no, dep_time, arr_delay, status
FROM flight WHERE flight_id = 1;

UPDATE flight SET dep_time = NULL, dep_delay = NULL, arr_time = NULL, arr_delay = NULL, air_time = NULL
WHERE flight_id = 1;

SELECT flight_id, flight_date, carrier, flight_no, dep_time, arr_delay, status
FROM flight WHERE flight_id = 1;

\echo '== D3  Integrity: the database refuses bad rows'
DO $$
BEGIN
    BEGIN
        INSERT INTO flight (flight_date, carrier, flight_no, origin, dest, sched_dep_time, sched_arr_time, time_hour)
        VALUES ('2013-06-01', 'ZZ', 1, 'JFK', 'LAX', 900, 1200, '2013-06-01 13:00+00');
    EXCEPTION WHEN foreign_key_violation THEN
        RAISE NOTICE 'rejected unknown airline ZZ: %', SQLERRM;
    END;
    BEGIN
        INSERT INTO flight (flight_date, carrier, flight_no, origin, dest, sched_dep_time, sched_arr_time, time_hour)
        VALUES ('2013-06-01', 'DL', 1, 'JFK', 'XYZ', 900, 1200, '2013-06-01 13:00+00');
    EXCEPTION WHEN foreign_key_violation THEN
        RAISE NOTICE 'rejected route JFK-XYZ: %', SQLERRM;
    END;
    BEGIN
        INSERT INTO flight (flight_date, carrier, flight_no, origin, dest, sched_dep_time, sched_arr_time, time_hour)
        VALUES ('2013-06-01', 'DL', 1, 'JFK', 'LAX', 2575, 1200, '2013-06-01 13:00+00');
    EXCEPTION WHEN check_violation THEN
        RAISE NOTICE 'rejected departure time 25:75: %', SQLERRM;
    END;
END $$;

\echo '== D4  Function: July scorecard'
SELECT * FROM carrier_report(7);

ROLLBACK;
