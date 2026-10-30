-- NYCFlights — 02_ddl.sql
-- 7 tables in BCNF. Run on an empty database `nycflights`:
--   psql -h localhost -U postgres -d nycflights -f 02_ddl.sql

DROP SCHEMA IF EXISTS nycflights CASCADE;
CREATE SCHEMA nycflights;
SET search_path = nycflights;

-- tzone -> utc_offset was split out of airport (transitive dependency faa -> tzone -> utc_offset).
CREATE TABLE timezone (
    tzone       VARCHAR(40) PRIMARY KEY,
    utc_offset  SMALLINT    NOT NULL CHECK (utc_offset BETWEEN -12 AND 14)
);

CREATE TABLE airport (
    faa        CHAR(3)      PRIMARY KEY,
    name       VARCHAR(100),
    lat        NUMERIC(9,6) CHECK (lat BETWEEN -90 AND 90),
    lon        NUMERIC(9,6) CHECK (lon BETWEEN -180 AND 180),
    alt_ft     INTEGER,
    dst        CHAR(1)      CHECK (dst IN ('A','U','N')),   -- A = US DST, U = unknown, N = none
    tzone      VARCHAR(40)  REFERENCES timezone,
    in_source  BOOLEAN      NOT NULL DEFAULT TRUE           -- FALSE = placeholder for a code used by flights only
);

CREATE TABLE airline (
    carrier  CHAR(2)      PRIMARY KEY,
    name     VARCHAR(60)  NOT NULL UNIQUE
);

CREATE TABLE plane (
    tailnum       VARCHAR(8)  PRIMARY KEY,
    year_built    SMALLINT    CHECK (year_built BETWEEN 1950 AND 2013),
    type          VARCHAR(40),
    manufacturer  VARCHAR(40),
    model         VARCHAR(30),
    engines       SMALLINT    CHECK (engines BETWEEN 1 AND 4),
    seats         SMALLINT    CHECK (seats > 0),
    speed         SMALLINT,
    engine        VARCHAR(20),
    in_source     BOOLEAN     NOT NULL DEFAULT TRUE
);

-- (origin, dest) -> distance, so distance lives here and not on every flight.
CREATE TABLE route (
    origin       CHAR(3)  REFERENCES airport,
    dest         CHAR(3)  REFERENCES airport,
    distance_mi  SMALLINT NOT NULL CHECK (distance_mi > 0),
    PRIMARY KEY (origin, dest),
    CHECK (origin <> dest)
);

CREATE TABLE weather (
    origin        CHAR(3)      REFERENCES airport,
    time_hour     TIMESTAMPTZ,
    temp_f        NUMERIC(5,2),
    dewp_f        NUMERIC(5,2),
    humid         NUMERIC(5,2) CHECK (humid BETWEEN 0 AND 100),
    wind_dir      SMALLINT     CHECK (wind_dir BETWEEN 0 AND 360),
    wind_speed    NUMERIC(6,2) CHECK (wind_speed >= 0),
    wind_gust     NUMERIC(6,2),
    precip_in     NUMERIC(5,2) CHECK (precip_in >= 0),
    pressure_mb   NUMERIC(6,1),
    visib_mi      NUMERIC(4,1) CHECK (visib_mi BETWEEN 0 AND 10),
    PRIMARY KEY (origin, time_hour)
);

-- year/month/day/hour/minute from the source are dropped: they are derivable
-- from flight_date and sched_dep_time. Weather is joined on (origin, time_hour)
-- without an FK because 1,556 flights fall in hours with no weather reading.
CREATE TABLE flight (
    flight_id       INTEGER     GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    flight_date     DATE        NOT NULL,
    carrier         CHAR(2)     NOT NULL REFERENCES airline,
    flight_no       SMALLINT    NOT NULL,
    tailnum         VARCHAR(8)  REFERENCES plane,
    origin          CHAR(3)     NOT NULL,
    dest            CHAR(3)     NOT NULL,
    sched_dep_time  SMALLINT    NOT NULL CHECK (sched_dep_time BETWEEN 0 AND 2359),
    dep_time        SMALLINT    CHECK (dep_time BETWEEN 1 AND 2400),
    dep_delay       SMALLINT,
    sched_arr_time  SMALLINT    NOT NULL CHECK (sched_arr_time BETWEEN 0 AND 2359),
    arr_time        SMALLINT    CHECK (arr_time BETWEEN 1 AND 2400),
    arr_delay       SMALLINT,
    air_time        SMALLINT    CHECK (air_time > 0),
    time_hour       TIMESTAMPTZ NOT NULL,
    status          VARCHAR(9)  NOT NULL,                  -- set by trigger trg_flight_status
    FOREIGN KEY (origin, dest) REFERENCES route,
    UNIQUE (carrier, flight_no, origin, flight_date),      -- natural candidate key
    CHECK (dep_time IS NOT NULL OR dep_delay IS NULL)       -- a cancelled flight has no delay
);
