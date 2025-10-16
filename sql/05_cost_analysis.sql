-- Cost estimation and analysis for Example forecasting workloads.
-- This script demonstrates cost estimation (no special privileges required)
-- and links to comprehensive monitoring queries in 06_monitoring_queries.sql.

-- For detailed monitoring including actual credit usage, see: sql/06_monitoring_queries.sql
-- That script provides real-time warehouse performance, query-level cost attribution,
-- and workload-specific analytics using ACCOUNT_USAGE views.

-- ============================================================================
-- SECTION 1: COST ESTIMATION (NO SPECIAL PRIVILEGES REQUIRED)
-- ============================================================================

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

-- ============================================================================
-- SECTION 2: QUERY TAG-BASED COST ATTRIBUTION (REQUIRES ACCOUNT_USAGE)
-- ============================================================================

-- 2.1 Actual credit usage by workload type (last 7 days)
-- This query attributes real costs to each workload type using query tags
-- Uncomment if you have ACCOUNT_USAGE privileges:
/*
WITH tagged_queries AS (
    SELECT
        qh.query_id,
        qh.query_tag,
        qh.start_time,
        qh.total_elapsed_time / 1000 AS execution_time_seconds,
        wmh.credits_used,
        CASE
            WHEN qh.query_tag LIKE '%WORKLOAD:TRAINING%' THEN 'TRAINING'
            WHEN qh.query_tag LIKE '%WORKLOAD:INFERENCE%' THEN 'INFERENCE'
            WHEN qh.query_tag LIKE '%WORKLOAD:DATA_PREP%' THEN 'DATA_PREP'
            ELSE 'UNTAGGED'
        END AS workload_type,
        CASE
            WHEN qh.query_tag LIKE '%PATH:ML_FUNCTIONS%' THEN 'ML_FUNCTIONS'
            WHEN qh.query_tag LIKE '%PATH:SNOWPARK_XGBOOST%' THEN 'SNOWPARK_XGBOOST'
            ELSE 'OTHER'
        END AS model_path
    FROM SNOWFLAKE.ACCOUNT_USAGE.QUERY_HISTORY qh
    LEFT JOIN SNOWFLAKE.ACCOUNT_USAGE.WAREHOUSE_METERING_HISTORY wmh
        ON qh.warehouse_name = wmh.warehouse_name
        AND DATE_TRUNC('hour', qh.start_time) = DATE_TRUNC('hour', wmh.start_time)
    WHERE qh.warehouse_name = 'SFE_SP_WH'
      AND qh.start_time >= DATEADD(day, -7, CURRENT_TIMESTAMP())
      AND qh.execution_status = 'SUCCESS'
)
SELECT
    workload_type,
    model_path,
    COUNT(DISTINCT query_id) AS query_count,
    ROUND(SUM(execution_time_seconds) / 3600, 2) AS total_execution_hours,
    ROUND(SUM(credits_used), 4) AS total_credits,
    ROUND(AVG(credits_used), 6) AS avg_credits_per_query,
    ROUND(SUM(credits_used) * (SELECT param_value FROM SNOWFLAKE_EXAMPLE.FORECASTING.SFE_COST_PARAMS WHERE param_name = 'DOLLARS_PER_CREDIT'), 2) AS estimated_cost_dollars
FROM tagged_queries
GROUP BY workload_type, model_path
ORDER BY total_credits DESC;
*/

-- 2.2 Cost comparison: ML Functions vs Snowpark XGBoost paths
-- Compare the two forecasting approaches by actual costs
-- Uncomment if you have ACCOUNT_USAGE privileges:
/*
WITH path_comparison AS (
    SELECT
        qh.query_tag,
        CASE
            WHEN qh.query_tag LIKE '%PATH:ML_FUNCTIONS%' THEN 'ML_FUNCTIONS'
            WHEN qh.query_tag LIKE '%PATH:SNOWPARK_XGBOOST%' THEN 'SNOWPARK_XGBOOST'
        END AS model_path,
        CASE
            WHEN qh.query_tag LIKE '%WORKLOAD:TRAINING%' THEN 'TRAINING'
            WHEN qh.query_tag LIKE '%WORKLOAD:INFERENCE%' THEN 'INFERENCE'
        END AS workload_type,
        qh.total_elapsed_time / 1000 AS execution_time_seconds,
        wmh.credits_used
    FROM SNOWFLAKE.ACCOUNT_USAGE.QUERY_HISTORY qh
    LEFT JOIN SNOWFLAKE.ACCOUNT_USAGE.WAREHOUSE_METERING_HISTORY wmh
        ON qh.warehouse_name = wmh.warehouse_name
        AND DATE_TRUNC('hour', qh.start_time) = DATE_TRUNC('hour', wmh.start_time)
    WHERE qh.warehouse_name = 'SFE_SP_WH'
      AND qh.start_time >= DATEADD(day, -14, CURRENT_TIMESTAMP())
      AND qh.execution_status = 'SUCCESS'
      AND qh.query_tag IS NOT NULL
      AND (qh.query_tag LIKE '%PATH:ML_FUNCTIONS%' OR qh.query_tag LIKE '%PATH:SNOWPARK_XGBOOST%')
)
SELECT
    model_path,
    workload_type,
    COUNT(*) AS execution_count,
    ROUND(AVG(execution_time_seconds), 2) AS avg_seconds,
    ROUND(SUM(credits_used), 4) AS total_credits,
    ROUND(SUM(credits_used) * (SELECT param_value FROM SNOWFLAKE_EXAMPLE.FORECASTING.SFE_COST_PARAMS WHERE param_name = 'DOLLARS_PER_CREDIT'), 2) AS total_cost_dollars,
    ROUND(AVG(credits_used) * (SELECT param_value FROM SNOWFLAKE_EXAMPLE.FORECASTING.SFE_COST_PARAMS WHERE param_name = 'DOLLARS_PER_CREDIT'), 4) AS avg_cost_per_run_dollars
FROM path_comparison
WHERE model_path IS NOT NULL AND workload_type IS NOT NULL
GROUP BY model_path, workload_type
ORDER BY model_path, workload_type;
*/

-- ============================================================================
-- SECTION 3: WAREHOUSE EFFICIENCY ANALYSIS
-- ============================================================================

-- 3.1 Recent warehouse activity summary (requires ACCOUNT_USAGE)
-- Uncomment to view actual warehouse usage patterns:
/*
SELECT
    warehouse_name,
    start_time,
    end_time,
    credits_used,
    DATEDIFF('minute', start_time, end_time) AS duration_minutes,
    ROUND(credits_used / NULLIF(DATEDIFF('hour', start_time, end_time), 0), 4) AS credits_per_hour
FROM SNOWFLAKE.ACCOUNT_USAGE.WAREHOUSE_METERING_HISTORY
WHERE warehouse_name = 'SFE_SP_WH'
  AND start_time >= DATEADD(day, -7, CURRENT_TIMESTAMP())
ORDER BY start_time DESC
LIMIT 20;
*/

-- ============================================================================
-- NEXT STEPS: COMPREHENSIVE MONITORING
-- ============================================================================

-- For comprehensive monitoring queries including:
--   - Warehouse performance and queuing detection
--   - Detailed cost attribution by query tag
--   - Query performance analysis
--   - Warehouse efficiency metrics
--   - Forecasting workload insights
--
-- Run the queries in: sql/06_monitoring_queries.sql
--
-- For interactive visualizations, use the Streamlit dashboard:
--   cd streamlit/monitoring && streamlit run app.py
