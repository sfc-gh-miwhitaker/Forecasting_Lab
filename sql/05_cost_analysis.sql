-- Cost estimation examples for Example forecasting workloads.
-- This script demonstrates how to use the cost estimator function created in 00_setup.sql.
-- It does NOT require special ORGANIZATION_USAGE or ACCOUNT_USAGE privileges.

-- 1. View the cost parameters that were configured
SELECT * FROM SNOWFLAKE_EXAMPLE.FORECASTING.SFE_COST_PARAMS;

-- 2. Example: Estimate cost for a 2-hour training job on Medium Snowpark-optimized warehouse
SELECT
    'Training Job (2 hours)' AS scenario,
    SNOWFLAKE_EXAMPLE.FORECASTING.SFE_ESTIMATE_WH_COST(
        2.0,  -- runtime_hours
        (SELECT PARAM_VALUE FROM SNOWFLAKE_EXAMPLE.FORECASTING.SFE_COST_PARAMS WHERE PARAM_NAME='SP_WH_MEDIUM_CREDITS_PER_HOUR'),
        (SELECT PARAM_VALUE FROM SNOWFLAKE_EXAMPLE.FORECASTING.SFE_COST_PARAMS WHERE PARAM_NAME='DOLLARS_PER_CREDIT')
    ) AS cost_estimate;

-- 3. Example: Estimate cost for daily forecasting (15 minutes/day for 30 days)
SELECT
    'Daily Forecasting (30 days @ 15 min/day)' AS scenario,
    SNOWFLAKE_EXAMPLE.FORECASTING.SFE_ESTIMATE_WH_COST(
        (15.0 / 60) * 30,  -- runtime_hours (0.25 hours * 30 days = 7.5 hours)
        (SELECT PARAM_VALUE FROM SNOWFLAKE_EXAMPLE.FORECASTING.SFE_COST_PARAMS WHERE PARAM_NAME='SP_WH_MEDIUM_CREDITS_PER_HOUR'),
        (SELECT PARAM_VALUE FROM SNOWFLAKE_EXAMPLE.FORECASTING.SFE_COST_PARAMS WHERE PARAM_NAME='DOLLARS_PER_CREDIT')
    ) AS cost_estimate;

-- 4. Example: Compare different warehouse sizes (assuming you scale up)
-- Note: Update the credits_per_hour values based on Snowflake's rate schedule for Snowpark-optimized warehouses:
-- https://docs.snowflake.com/en/user-guide/warehouses-overview#warehouse-size
WITH scenarios AS (
    SELECT 'Small' AS size, 2.0 AS credits_per_hour, 1.0 AS runtime_hours UNION ALL
    SELECT 'Medium', 6.0, 1.0 UNION ALL
    SELECT 'Large', 16.0, 1.0
)
SELECT
    size,
    runtime_hours,
    credits_per_hour,
    SNOWFLAKE_EXAMPLE.FORECASTING.SFE_ESTIMATE_WH_COST(
        runtime_hours,
        credits_per_hour,
        (SELECT PARAM_VALUE FROM SNOWFLAKE_EXAMPLE.FORECASTING.SFE_COST_PARAMS WHERE PARAM_NAME='DOLLARS_PER_CREDIT')
    ) AS cost_estimate
FROM scenarios;

-- Optional: If you have ACCOUNT_USAGE access, you can check actual warehouse usage
-- Uncomment the following query to see recent warehouse activity:
/*
SELECT
    WAREHOUSE_NAME,
    START_TIME,
    END_TIME,
    CREDITS_USED,
    DATEDIFF('minute', START_TIME, END_TIME) AS duration_minutes
FROM SNOWFLAKE.ACCOUNT_USAGE.WAREHOUSE_METERING_HISTORY
WHERE WAREHOUSE_NAME = 'SFE_SP_WH'
  AND START_TIME >= DATEADD(day, -7, CURRENT_TIMESTAMP())
ORDER BY START_TIME DESC
LIMIT 20;
*/
