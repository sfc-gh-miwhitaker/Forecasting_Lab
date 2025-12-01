/*******************************************************************************
 * DEMO PROJECT: Forecasting Lab
 * Script: Monitoring - Warehouse Performance and Cost Metrics
 * 
 * ⚠️  NOT FOR PRODUCTION USE - EXAMPLE IMPLEMENTATION ONLY
 * 
 * PURPOSE:
 *   Comprehensive monitoring queries for tracking warehouse utilization,
 *   query performance, cost attribution, and efficiency metrics. Uses
 *   ACCOUNT_USAGE views for historical analysis.
 * 
 * SECTIONS:
 *   1. Warehouse Performance (utilization, queuing detection)
 *   2. Cost Attribution by Query Tag (workload type, model path)
 *   3. Query Performance Analysis (slow queries, spillage detection)
 *   4. Warehouse Efficiency Metrics (idle time, compute efficiency)
 *   5. Forecasting-Specific Insights (training vs inference costs)
 *   6. Resource Monitor Examples (optional budget controls)
 * 
 * PREREQUISITES:
 *   - IMPORTED PRIVILEGES on SNOWFLAKE database
 *   - Or ACCOUNTADMIN role
 *   - Workloads executed with query tags for attribution
 * 
 * NOTE:
 *   ACCOUNT_USAGE views have latency (up to 45 minutes for QUERY_HISTORY).
 *   For real-time monitoring, use INFORMATION_SCHEMA views where available.
 * 
 * SEE ALSO:
 *   - sql/04_monitoring/05_cost_analysis.sql (cost estimation)
 *   - streamlit/monitoring/SFE_MONITORING_DASHBOARD.py (interactive dashboard)
 *   - docs/02-MONITORING.md (monitoring guide)
 * 
 * CLEANUP:
 *   See sql/99_cleanup/99_cleanup.sql
 ******************************************************************************/

-- Cost and Performance Monitoring Queries for Forecasting Workloads
-- These queries help track warehouse utilization, identify performance bottlenecks, and attribute costs
-- Reference: https://docs.snowflake.com/en/sql-reference/account-usage

-- Note: ACCOUNT_USAGE views have latency (up to 45 minutes for QUERY_HISTORY)
-- For real-time monitoring, use INFORMATION_SCHEMA views where available

USE SCHEMA SNOWFLAKE_EXAMPLE.FORECASTING;

-- ============================================================================
-- SECTION 1: WAREHOUSE PERFORMANCE MONITORING
-- ============================================================================

-- 1.1 Warehouse utilization over the last 7 days
-- Helps identify peak usage periods and potential over/under-provisioning
SELECT
    warehouse_name,
    DATE_TRUNC('hour', start_time) AS hour,
    SUM(credits_used) AS total_credits,
    COUNT(*) AS execution_count,
    AVG(credits_used) AS avg_credits_per_execution
FROM SNOWFLAKE.ACCOUNT_USAGE.WAREHOUSE_METERING_HISTORY
WHERE warehouse_name = 'SFE_SP_WH'
  AND start_time >= DATEADD(day, -7, CURRENT_TIMESTAMP())
GROUP BY warehouse_name, DATE_TRUNC('hour', start_time)
ORDER BY hour DESC;

-- 1.2 Warehouse load history (detect queuing issues)
-- High average_running or average_queued_load indicates need for larger warehouse or multi-cluster
SELECT
    warehouse_name,
    start_time,
    end_time,
    avg_running AS average_running_queries,
    avg_queued_load AS average_queued_queries,
    avg_queued_provisioning AS average_queued_for_provisioning,
    avg_blocked AS average_blocked_queries
FROM SNOWFLAKE.ACCOUNT_USAGE.WAREHOUSE_LOAD_HISTORY
WHERE warehouse_name = 'SFE_SP_WH'
  AND start_time >= DATEADD(day, -7, CURRENT_TIMESTAMP())
  AND (avg_queued_load > 0 OR avg_blocked > 0)  -- Only show periods with queuing
ORDER BY start_time DESC
LIMIT 100;

-- 1.3 Real-time warehouse load (uses INFORMATION_SCHEMA for near-instant results)
-- Run this query to check current warehouse status
SHOW PARAMETERS LIKE 'statement%' FOR WAREHOUSE SFE_SP_WH;

-- ============================================================================
-- SECTION 2: COST ANALYSIS BY QUERY TAG
-- ============================================================================

-- 2.1 Credit consumption by workload type (last 14 days)
-- Shows cost attribution across training, inference, and data prep workloads
WITH tagged_queries AS (
    SELECT
        qh.query_id,
        qh.query_tag,
        qh.warehouse_name,
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
      AND qh.start_time >= DATEADD(day, -14, CURRENT_TIMESTAMP())
      AND qh.execution_status = 'SUCCESS'
)
SELECT
    workload_type,
    COUNT(DISTINCT query_id) AS query_count,
    SUM(execution_time_seconds) / 3600 AS total_execution_hours,
    SUM(credits_used) AS total_credits,
    AVG(credits_used) AS avg_credits_per_query,
    SUM(credits_used) * (SELECT param_value FROM SFE_COST_PARAMS WHERE param_name = 'DOLLARS_PER_CREDIT') AS estimated_cost_dollars
FROM tagged_queries
GROUP BY workload_type
ORDER BY total_credits DESC;

-- 2.2 Cost comparison: ML Functions vs Snowpark XGBoost
-- Compare the two forecasting approaches by cost and performance
WITH tagged_queries AS (
    SELECT
        qh.query_id,
        qh.query_tag,
        qh.warehouse_name,
        qh.start_time,
        qh.total_elapsed_time / 1000 AS execution_time_seconds,
        wmh.credits_used,
        CASE
            WHEN qh.query_tag LIKE '%WORKLOAD:TRAINING%' THEN 'TRAINING'
            WHEN qh.query_tag LIKE '%WORKLOAD:INFERENCE%' THEN 'INFERENCE'
            ELSE 'OTHER'
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
      AND qh.start_time >= DATEADD(day, -14, CURRENT_TIMESTAMP())
      AND qh.execution_status = 'SUCCESS'
      AND qh.query_tag IS NOT NULL
)
SELECT
    model_path,
    workload_type,
    COUNT(DISTINCT query_id) AS query_count,
    ROUND(AVG(execution_time_seconds), 2) AS avg_execution_seconds,
    ROUND(SUM(credits_used), 4) AS total_credits,
    ROUND(AVG(credits_used), 6) AS avg_credits_per_query,
    ROUND(SUM(credits_used) * (SELECT param_value FROM SFE_COST_PARAMS WHERE param_name = 'DOLLARS_PER_CREDIT'), 2) AS estimated_cost_dollars
FROM tagged_queries
WHERE model_path != 'OTHER'
GROUP BY model_path, workload_type
ORDER BY model_path, workload_type;

-- 2.3 Daily credit consumption trend
-- Visualize cost trends over time to identify anomalies
SELECT
    DATE_TRUNC('day', start_time) AS date,
    warehouse_name,
    SUM(credits_used) AS daily_credits,
    SUM(credits_used) * (SELECT param_value FROM SFE_COST_PARAMS WHERE param_name = 'DOLLARS_PER_CREDIT') AS daily_cost_dollars
FROM SNOWFLAKE.ACCOUNT_USAGE.WAREHOUSE_METERING_HISTORY
WHERE warehouse_name = 'SFE_SP_WH'
  AND start_time >= DATEADD(day, -30, CURRENT_TIMESTAMP())
GROUP BY DATE_TRUNC('day', start_time), warehouse_name
ORDER BY date DESC;

-- ============================================================================
-- SECTION 3: QUERY PERFORMANCE ANALYSIS
-- ============================================================================

-- 3.1 Top 20 longest-running queries (last 7 days)
-- Identify queries that may need optimization
SELECT
    query_id,
    query_tag,
    user_name,
    warehouse_name,
    start_time,
    end_time,
    total_elapsed_time / 1000 AS execution_time_seconds,
    queued_provisioning_time / 1000 AS queue_provision_seconds,
    queued_repair_time / 1000 AS queue_repair_seconds,
    queued_overload_time / 1000 AS queue_overload_seconds,
    bytes_scanned,
    rows_produced
FROM SNOWFLAKE.ACCOUNT_USAGE.QUERY_HISTORY
WHERE warehouse_name = 'SFE_SP_WH'
  AND start_time >= DATEADD(day, -7, CURRENT_TIMESTAMP())
  AND execution_status = 'SUCCESS'
ORDER BY total_elapsed_time DESC
LIMIT 20;

-- 3.2 Most expensive queries by credits (last 7 days)
-- Find queries consuming the most compute resources
WITH query_credits AS (
    SELECT
        qh.query_id,
        qh.query_tag,
        qh.query_text,
        qh.user_name,
        qh.start_time,
        qh.total_elapsed_time / 1000 AS execution_time_seconds,
        wmh.credits_used
    FROM SNOWFLAKE.ACCOUNT_USAGE.QUERY_HISTORY qh
    LEFT JOIN SNOWFLAKE.ACCOUNT_USAGE.WAREHOUSE_METERING_HISTORY wmh
        ON qh.warehouse_name = wmh.warehouse_name
        AND DATE_TRUNC('hour', qh.start_time) = DATE_TRUNC('hour', wmh.start_time)
    WHERE qh.warehouse_name = 'SFE_SP_WH'
      AND qh.start_time >= DATEADD(day, -7, CURRENT_TIMESTAMP())
      AND qh.execution_status = 'SUCCESS'
)
SELECT
    query_id,
    query_tag,
    SUBSTRING(query_text, 1, 100) AS query_preview,
    user_name,
    start_time,
    execution_time_seconds,
    credits_used,
    credits_used * (SELECT param_value FROM SFE_COST_PARAMS WHERE param_name = 'DOLLARS_PER_CREDIT') AS estimated_cost_dollars
FROM query_credits
WHERE credits_used IS NOT NULL
ORDER BY credits_used DESC
LIMIT 20;

-- 3.3 Query execution patterns by hour of day
-- Understand when workloads run to optimize scheduling
SELECT
    HOUR(start_time) AS hour_of_day,
    COUNT(*) AS query_count,
    AVG(total_elapsed_time / 1000) AS avg_execution_seconds,
    SUM(CASE WHEN queued_overload_time > 0 THEN 1 ELSE 0 END) AS queries_queued
FROM SNOWFLAKE.ACCOUNT_USAGE.QUERY_HISTORY
WHERE warehouse_name = 'SFE_SP_WH'
  AND start_time >= DATEADD(day, -7, CURRENT_TIMESTAMP())
  AND execution_status = 'SUCCESS'
GROUP BY HOUR(start_time)
ORDER BY hour_of_day;

-- ============================================================================
-- SECTION 4: WAREHOUSE EFFICIENCY METRICS
-- ============================================================================

-- 4.1 Warehouse idle time analysis
-- Detect periods where warehouse is running but not executing queries (wasted credits)
WITH warehouse_sessions AS (
    SELECT
        warehouse_name,
        start_time,
        end_time,
        credits_used,
        DATEDIFF('second', start_time, end_time) / 3600.0 AS session_hours
    FROM SNOWFLAKE.ACCOUNT_USAGE.WAREHOUSE_METERING_HISTORY
    WHERE warehouse_name = 'SFE_SP_WH'
      AND start_time >= DATEADD(day, -7, CURRENT_TIMESTAMP())
),
query_time AS (
    SELECT
        warehouse_name,
        SUM(total_elapsed_time) / 1000.0 / 3600.0 AS active_query_hours
    FROM SNOWFLAKE.ACCOUNT_USAGE.QUERY_HISTORY
    WHERE warehouse_name = 'SFE_SP_WH'
      AND start_time >= DATEADD(day, -7, CURRENT_TIMESTAMP())
      AND execution_status = 'SUCCESS'
    GROUP BY warehouse_name
)
SELECT
    ws.warehouse_name,
    SUM(ws.session_hours) AS total_warehouse_hours,
    qt.active_query_hours,
    SUM(ws.session_hours) - qt.active_query_hours AS idle_hours,
    ROUND(100.0 * (SUM(ws.session_hours) - qt.active_query_hours) / NULLIF(SUM(ws.session_hours), 0), 2) AS idle_percentage,
    SUM(ws.credits_used) AS total_credits,
    ROUND(SUM(ws.credits_used) * (SUM(ws.session_hours) - qt.active_query_hours) / NULLIF(SUM(ws.session_hours), 0), 4) AS estimated_idle_credits
FROM warehouse_sessions ws
JOIN query_time qt ON ws.warehouse_name = qt.warehouse_name
GROUP BY ws.warehouse_name, qt.active_query_hours;

-- 4.2 Auto-suspend effectiveness
-- Check if auto-suspend timeout is appropriate for workload patterns
SELECT
    warehouse_name,
    DATE_TRUNC('day', start_time) AS date,
    COUNT(*) AS session_count,
    AVG(DATEDIFF('second', start_time, end_time)) AS avg_session_duration_seconds,
    MIN(DATEDIFF('second', start_time, end_time)) AS min_session_duration_seconds,
    MAX(DATEDIFF('second', start_time, end_time)) AS max_session_duration_seconds
FROM SNOWFLAKE.ACCOUNT_USAGE.WAREHOUSE_METERING_HISTORY
WHERE warehouse_name = 'SFE_SP_WH'
  AND start_time >= DATEADD(day, -7, CURRENT_TIMESTAMP())
GROUP BY warehouse_name, DATE_TRUNC('day', start_time)
ORDER BY date DESC;

-- ============================================================================
-- SECTION 5: FORECASTING WORKLOAD INSIGHTS
-- ============================================================================

-- 5.1 Model training frequency and duration
-- Track training job patterns
SELECT
    DATE_TRUNC('day', start_time) AS training_date,
    COUNT(*) AS training_runs,
    AVG(total_elapsed_time / 1000) AS avg_training_seconds,
    MAX(total_elapsed_time / 1000) AS max_training_seconds,
    SUM(bytes_scanned) / POWER(1024, 3) AS total_gb_scanned
FROM SNOWFLAKE.ACCOUNT_USAGE.QUERY_HISTORY
WHERE warehouse_name = 'SFE_SP_WH'
  AND query_tag LIKE '%WORKLOAD:TRAINING%'
  AND start_time >= DATEADD(day, -30, CURRENT_TIMESTAMP())
  AND execution_status = 'SUCCESS'
GROUP BY DATE_TRUNC('day', start_time)
ORDER BY training_date DESC;

-- 5.2 Inference workload statistics
-- Monitor forecasting query performance
SELECT
    DATE_TRUNC('day', start_time) AS inference_date,
    COUNT(*) AS inference_runs,
    AVG(total_elapsed_time / 1000) AS avg_inference_seconds,
    MIN(total_elapsed_time / 1000) AS min_inference_seconds,
    MAX(total_elapsed_time / 1000) AS max_inference_seconds,
    AVG(rows_produced) AS avg_rows_forecasted
FROM SNOWFLAKE.ACCOUNT_USAGE.QUERY_HISTORY
WHERE warehouse_name = 'SFE_SP_WH'
  AND query_tag LIKE '%WORKLOAD:INFERENCE%'
  AND start_time >= DATEADD(day, -30, CURRENT_TIMESTAMP())
  AND execution_status = 'SUCCESS'
GROUP BY DATE_TRUNC('day', start_time)
ORDER BY inference_date DESC;

-- ============================================================================
-- SECTION 6: OPTIONAL AUTOMATED RESOURCE MONITOR (EXAMPLE)
-- ============================================================================

-- 6.1 Example: Create automated alerting with resource monitors
-- Uncomment to enable automated cost controls and notifications
/*
-- Create a resource monitor with progressive alerts
CREATE OR REPLACE RESOURCE MONITOR SFE_FORECASTING_MONITOR WITH
    CREDIT_QUOTA = 100  -- Set based on your monthly budget
    FREQUENCY = MONTHLY
    START_TIMESTAMP = IMMEDIATELY
    TRIGGERS
        ON 50 PERCENT DO NOTIFY  -- Early warning at 50%
        ON 75 PERCENT DO NOTIFY  -- Alert at 75%
        ON 90 PERCENT DO SUSPEND  -- Suspend new queries at 90%
        ON 100 PERCENT DO SUSPEND_IMMEDIATE;  -- Hard stop at 100%

-- Apply monitor to warehouse
ALTER WAREHOUSE SFE_SP_WH SET RESOURCE_MONITOR = SFE_FORECASTING_MONITOR;

-- View resource monitor status
SELECT
    name AS monitor_name,
    credit_quota,
    used_credits,
    remaining_credits,
    ROUND(100.0 * used_credits / credit_quota, 2) AS percent_used,
    frequency,
    start_time,
    end_time
FROM SNOWFLAKE.ACCOUNT_USAGE.RESOURCE_MONITORS
WHERE name = 'SFE_FORECASTING_MONITOR';

-- View triggered actions
SELECT
    resource_monitor_name,
    threshold,
    trigger_type,
    trigger_time
FROM SNOWFLAKE.ACCOUNT_USAGE.RESOURCE_MONITOR_ACTIONS
WHERE resource_monitor_name = 'SFE_FORECASTING_MONITOR'
ORDER BY trigger_time DESC;
*/

-- ============================================================================
-- SECTION 7: SUMMARY DASHBOARD QUERY
-- ============================================================================

-- 7.1 Executive summary: Last 7 days forecasting workload overview
SELECT
    'Warehouse Overview' AS metric_category,
    'Total Credits Used' AS metric_name,
    ROUND(SUM(credits_used), 2) AS metric_value,
    ROUND(SUM(credits_used) * (SELECT param_value FROM SFE_COST_PARAMS WHERE param_name = 'DOLLARS_PER_CREDIT'), 2) AS cost_dollars
FROM SNOWFLAKE.ACCOUNT_USAGE.WAREHOUSE_METERING_HISTORY
WHERE warehouse_name = 'SFE_SP_WH'
  AND start_time >= DATEADD(day, -7, CURRENT_TIMESTAMP())

UNION ALL

SELECT
    'Query Performance' AS metric_category,
    'Total Queries Executed' AS metric_name,
    COUNT(*) AS metric_value,
    NULL AS cost_dollars
FROM SNOWFLAKE.ACCOUNT_USAGE.QUERY_HISTORY
WHERE warehouse_name = 'SFE_SP_WH'
  AND start_time >= DATEADD(day, -7, CURRENT_TIMESTAMP())
  AND execution_status = 'SUCCESS'

UNION ALL

SELECT
    'Query Performance' AS metric_category,
    'Average Query Time (seconds)' AS metric_name,
    ROUND(AVG(total_elapsed_time / 1000), 2) AS metric_value,
    NULL AS cost_dollars
FROM SNOWFLAKE.ACCOUNT_USAGE.QUERY_HISTORY
WHERE warehouse_name = 'SFE_SP_WH'
  AND start_time >= DATEADD(day, -7, CURRENT_TIMESTAMP())
  AND execution_status = 'SUCCESS'

UNION ALL

SELECT
    'Workload Attribution' AS metric_category,
    'Training Runs' AS metric_name,
    COUNT(*) AS metric_value,
    NULL AS cost_dollars
FROM SNOWFLAKE.ACCOUNT_USAGE.QUERY_HISTORY
WHERE warehouse_name = 'SFE_SP_WH'
  AND query_tag LIKE '%WORKLOAD:TRAINING%'
  AND start_time >= DATEADD(day, -7, CURRENT_TIMESTAMP())
  AND execution_status = 'SUCCESS'

UNION ALL

SELECT
    'Workload Attribution' AS metric_category,
    'Inference Runs' AS metric_name,
    COUNT(*) AS metric_value,
    NULL AS cost_dollars
FROM SNOWFLAKE.ACCOUNT_USAGE.QUERY_HISTORY
WHERE warehouse_name = 'SFE_SP_WH'
  AND query_tag LIKE '%WORKLOAD:INFERENCE%'
  AND start_time >= DATEADD(day, -7, CURRENT_TIMESTAMP())
  AND execution_status = 'SUCCESS'

ORDER BY metric_category, metric_name;

