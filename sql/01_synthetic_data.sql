-- Generates synthetic time-series data for the forecasting model example.

-- 1. Recreate the target table for forecast input data to ensure correct schema.
DROP TABLE IF EXISTS SNOWFLAKE_EXAMPLE.FORECASTING.FORECAST_INPUT_GLOBAL;
CREATE TABLE SNOWFLAKE_EXAMPLE.FORECASTING.FORECAST_INPUT_GLOBAL (
    REGION STRING,
    ISRC STRING,
    DISPLAY_ARTIST STRING,
    TRACK STRING,
    RELEASE_DATE DATE,
    WEEK_ENDING DATE,
    STREAMS NUMBER(38,0)
);

-- 2. Generate synthetic data for both Global and US regions and insert.
INSERT INTO SNOWFLAKE_EXAMPLE.FORECASTING.FORECAST_INPUT_GLOBAL
WITH base_tracks AS (
    SELECT
        column1 AS isrc,
        column2 AS display_artist,
        column3 AS track,
        column4 AS release_date
    FROM VALUES
        ('TRK001', 'Artist One', 'Track One', DATEADD(week, -120, CURRENT_DATE())),
        ('TRK002', 'Artist Two', 'Track Two', DATEADD(week, - 90, CURRENT_DATE())),
        ('TRK003', 'Artist Three', 'Track Three', DATEADD(week, - 60, CURRENT_DATE()))
),
expanded AS (
    SELECT
        t.isrc,
        t.display_artist,
        t.track,
        t.release_date,
        seq4() AS seq
    FROM base_tracks t,
         TABLE(GENERATOR(ROWCOUNT => 52))
),
scored AS (
    SELECT
        isrc,
        display_artist,
        track,
        release_date,
        DATEADD(week, - (seq + 1), CURRENT_DATE()) AS week_ending,
        ROW_NUMBER() OVER (PARTITION BY isrc ORDER BY seq) AS week_number,
        750000
            + ROW_NUMBER() OVER (PARTITION BY isrc ORDER BY seq) * 12500
            + UNIFORM(-20000, 20000, RANDOM()) AS base_streams
    FROM expanded
)
SELECT
    region,
    isrc,
    display_artist,
    track,
    release_date,
    week_ending,
    streams
FROM (
    SELECT
        'Global' AS region,
        isrc,
        display_artist,
        track,
        release_date,
        week_ending,
        LEAST(GREATEST(base_streams, 50000), 5000000) AS streams
    FROM scored
    UNION ALL
    SELECT
        'US' AS region,
        isrc,
        display_artist,
        track,
        release_date,
        week_ending,
        LEAST(GREATEST(base_streams * 0.8 + UNIFORM(-15000, 15000, RANDOM()), 25000), 3500000) AS streams
    FROM scored
);

-- 3. Verify the data
-- SELECT * FROM SNOWFLAKE_EXAMPLE.FORECASTING.FORECAST_INPUT_GLOBAL WHERE REGION = 'Global' LIMIT 10;
