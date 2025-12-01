/*******************************************************************************
 * DEMO PROJECT: Forecasting Lab
 * Script: Cleanup - Complete Teardown
 * 
 * ⚠️  NOT FOR PRODUCTION USE - EXAMPLE IMPLEMENTATION ONLY
 * 
 * PURPOSE:
 *   Comprehensive cleanup script that removes ALL demo objects created
 *   during the lab. Includes cost summary queries for final expense review
 *   before deletion.
 * 
 * OBJECTS DROPPED:
 *   - SNOWFLAKE_EXAMPLE database (CASCADE - all schemas, tables, procedures)
 *   - SFE_SP_WH warehouse
 *   - SFE_MONITORING_DASHBOARD Streamlit app
 *   - Optional: SFE_FORECASTING_MONITOR resource monitor
 *   - Optional: Scheduled tasks (SFE_TASK_*)
 * 
 * COST REVIEW:
 *   Step 1 includes queries to review total credit consumption and
 *   workload-level costs before cleanup executes.
 * 
 * PREREQUISITES:
 *   - ACCOUNTADMIN role or ownership of objects
 *   - IMPORTED PRIVILEGES on SNOWFLAKE database (for cost queries)
 * 
 * WARNING:
 *   This script is DESTRUCTIVE and IRREVERSIBLE. All forecasting data,
 *   models, and configurations will be permanently deleted.
 * 
 * VERIFICATION:
 *   After cleanup, run: SHOW DATABASES LIKE 'SNOWFLAKE_EXAMPLE';
 *   Expected result: No rows returned
 ******************************************************************************/

-- Cleanup script for Example forecasting modernization
-- Drops the database, warehouse, and optional resource monitors to remove all lab-related objects.

-- ============================================================================
-- STEP 1: Review final costs before cleanup
-- ============================================================================

-- View total credits consumed during the lab
SELECT
    warehouse_name,
    MIN(start_time) AS first_usage,
    MAX(end_time) AS last_usage,
    SUM(credits_used) AS total_credits,
    ROUND(SUM(credits_used) * (SELECT param_value FROM SNOWFLAKE_EXAMPLE.FORECASTING.SFE_COST_PARAMS WHERE param_name = 'DOLLARS_PER_CREDIT'), 2) AS estimated_total_cost_dollars
FROM SNOWFLAKE.ACCOUNT_USAGE.WAREHOUSE_METERING_HISTORY
WHERE warehouse_name = 'SFE_SP_WH'
GROUP BY warehouse_name;

-- View workload breakdown by query tag
WITH tagged_queries AS (
    SELECT
        qh.query_tag,
        CASE
            WHEN qh.query_tag LIKE '%WORKLOAD:TRAINING%' THEN 'TRAINING'
            WHEN qh.query_tag LIKE '%WORKLOAD:INFERENCE%' THEN 'INFERENCE'
            WHEN qh.query_tag LIKE '%WORKLOAD:DATA_PREP%' THEN 'DATA_PREP'
            ELSE 'UNTAGGED'
        END AS workload_type,
        wmh.credits_used
    FROM SNOWFLAKE.ACCOUNT_USAGE.QUERY_HISTORY qh
    LEFT JOIN SNOWFLAKE.ACCOUNT_USAGE.WAREHOUSE_METERING_HISTORY wmh
        ON qh.warehouse_name = wmh.warehouse_name
        AND DATE_TRUNC('hour', qh.start_time) = DATE_TRUNC('hour', wmh.start_time)
    WHERE qh.warehouse_name = 'SFE_SP_WH'
      AND qh.execution_status = 'SUCCESS'
)
SELECT
    workload_type,
    COUNT(*) AS query_count,
    ROUND(SUM(credits_used), 4) AS total_credits,
    ROUND(SUM(credits_used) * (SELECT param_value FROM SNOWFLAKE_EXAMPLE.FORECASTING.SFE_COST_PARAMS WHERE param_name = 'DOLLARS_PER_CREDIT'), 2) AS estimated_cost_dollars
FROM tagged_queries
GROUP BY workload_type
ORDER BY total_credits DESC;

-- ============================================================================
-- STEP 2: Suspend any running tasks
-- ============================================================================

-- Suspend tasks to prevent execution during cleanup
-- Uncomment if tasks were created:
/*
ALTER TASK IF EXISTS SNOWFLAKE_EXAMPLE.FORECASTING.SFE_TASK_TRAIN_GLOBAL SUSPEND;
ALTER TASK IF EXISTS SNOWFLAKE_EXAMPLE.FORECASTING.SFE_TASK_FORECAST_GLOBAL SUSPEND;
ALTER TASK IF EXISTS SNOWFLAKE_EXAMPLE.FORECASTING.SFE_TASK_FORECAST_ML SUSPEND;
*/

-- ============================================================================
-- STEP 3: Remove resource monitors (if created)
-- ============================================================================

-- Remove resource monitor association and drop the monitor
-- Uncomment if resource monitor was created:
/*
ALTER WAREHOUSE SFE_SP_WH UNSET RESOURCE_MONITOR;
DROP RESOURCE MONITOR IF EXISTS SFE_FORECASTING_MONITOR;
*/

-- ============================================================================
-- STEP 4: Drop Streamlit dashboard
-- ============================================================================

-- Drop the monitoring dashboard Streamlit app
DROP STREAMLIT IF EXISTS SNOWFLAKE_EXAMPLE.FORECASTING.SFE_MONITORING_DASHBOARD;

-- ============================================================================
-- STEP 5: Drop all lab objects
-- ============================================================================

-- Drop database (includes all schemas, tables, procedures, functions, tasks, stages)
DROP DATABASE IF EXISTS SNOWFLAKE_EXAMPLE;

-- Drop warehouse
DROP WAREHOUSE IF EXISTS SFE_SP_WH;

-- ============================================================================
-- CLEANUP COMPLETE
-- ============================================================================
-- All forecasting lab objects have been removed.
-- Review the cost summary above to understand total lab expenses.