/*******************************************************************************
 * DEMO PROJECT: Forecasting Lab
 * Script: Setup - Database, Schema, and Warehouse Creation
 * 
 * ⚠️  NOT FOR PRODUCTION USE - EXAMPLE IMPLEMENTATION ONLY
 * 
 * PURPOSE:
 *   Creates SNOWFLAKE_EXAMPLE database, FORECASTING schema, and SFE_SP_WH
 *   Snowpark-optimized warehouse. Sets up cost estimation functions and
 *   query tagging infrastructure for both ML Functions and Snowpark paths.
 * 
 * OBJECTS CREATED:
 *   - SNOWFLAKE_EXAMPLE (Database)
 *   - SNOWFLAKE_EXAMPLE.FORECASTING (Schema)
 *   - SFE_SP_WH (Warehouse - Snowpark-Optimized MEDIUM)
 *   - SFE_MODEL_STAGE (Stage for XGBoost artifacts)
 *   - SFE_STREAMLIT_STAGE (Stage for dashboard files)
 *   - SFE_COST_PARAMS (Table for cost calculation parameters)
 *   - SFE_ESTIMATE_WH_COST (Function for cost estimation)
 * 
 * PREREQUISITES:
 *   - ACCOUNTADMIN role or CREATE DATABASE/WAREHOUSE privileges
 * 
 * CLEANUP:
 *   See sql/99_cleanup/99_cleanup.sql
 ******************************************************************************/

-- Snowflake setup script for Example Forecasting modernization
-- Creates database, schema, Snowpark-optimized warehouse, model stage, cost parameter table, and estimator functions.
-- Run inside Snowflake with appropriate privileges (ACCOUNTADMIN or delegated role).

-- ============================================================================
-- EXPIRATION CHECK
-- ============================================================================
-- This demo expires on 2025-12-24 (30 days from creation)
-- After expiration, this repository will be archived and made private

SELECT CASE
    WHEN CURRENT_DATE() > '2025-12-24'::DATE THEN
        ERROR('⚠️  DEMO EXPIRED: This demonstration project expired on 2025-12-24. ' ||
              'This code uses Snowflake features current as of November 2025. ' ||
              'Please check for updated versions or contact SE Community for current demos.')
    WHEN CURRENT_DATE() > DATEADD(day, -7, '2025-12-24'::DATE) THEN
        'WARNING: This demo will expire in ' || DATEDIFF(day, CURRENT_DATE(), '2025-12-24'::DATE) || ' days (on 2025-12-24)'
    ELSE
        'Demo is active. Expires: 2025-12-24'
END AS expiration_status;

-- ============================================================================
-- SETUP: Database and Schema
-- ============================================================================

-- 1. Database and schema
CREATE DATABASE IF NOT EXISTS SNOWFLAKE_EXAMPLE;
CREATE SCHEMA IF NOT EXISTS SNOWFLAKE_EXAMPLE.FORECASTING;

-- 2. Snowpark-optimized warehouse with performance and cost optimization best practices
-- Reference: https://docs.snowflake.com/en/user-guide/warehouses-overview
-- Best Practices:
--   - AUTO_SUSPEND = 60 seconds: Aggressive auto-suspend to minimize idle compute costs
--   - AUTO_RESUME = TRUE: Automatically restart when queries are submitted
--   - WAREHOUSE_SIZE = 'medium': Start small and scale up based on actual performance needs
--   - For production: Consider multi-cluster warehouses for high-concurrency workloads
CREATE WAREHOUSE IF NOT EXISTS SFE_SP_WH
    WAREHOUSE_SIZE = 'medium'
    WAREHOUSE_TYPE = 'SNOWPARK-OPTIMIZED'
    AUTO_SUSPEND = 60
    AUTO_RESUME = TRUE
    COMMENT = 'Forecasting workload warehouse: training, inference, and data preparation';

-- 3. Model stage for artifacts
CREATE STAGE IF NOT EXISTS SNOWFLAKE_EXAMPLE.FORECASTING.SFE_MODEL_STAGE;

-- 3a. Streamlit stage for monitoring dashboard
CREATE STAGE IF NOT EXISTS SNOWFLAKE_EXAMPLE.FORECASTING.SFE_STREAMLIT_STAGE
    COMMENT = 'Stage for Streamlit monitoring dashboard files';

-- 4. Cost parameter table (editable values)
CREATE TABLE IF NOT EXISTS SNOWFLAKE_EXAMPLE.FORECASTING.SFE_COST_PARAMS (
    PARAM_NAME STRING,
    PARAM_VALUE FLOAT,
    UPDATED_AT TIMESTAMP_LTZ DEFAULT CURRENT_TIMESTAMP()
);

-- Example seed values (update with contract specifics)
MERGE INTO SNOWFLAKE_EXAMPLE.FORECASTING.SFE_COST_PARAMS t
USING (
    SELECT 'DOLLARS_PER_CREDIT' AS PARAM_NAME, 3.00 AS PARAM_VALUE UNION ALL
    SELECT 'SP_WH_MEDIUM_CREDITS_PER_HOUR', 6.00
) s
ON t.PARAM_NAME = s.PARAM_NAME
WHEN MATCHED THEN UPDATE SET PARAM_VALUE = s.PARAM_VALUE, UPDATED_AT = CURRENT_TIMESTAMP()
WHEN NOT MATCHED THEN INSERT (PARAM_NAME, PARAM_VALUE) VALUES (s.PARAM_NAME, s.PARAM_VALUE);

-- 5. Estimator functions
CREATE OR REPLACE FUNCTION SNOWFLAKE_EXAMPLE.FORECASTING.SFE_ESTIMATE_WH_COST(
    RUNTIME_HOURS FLOAT,
    CREDITS_PER_HOUR FLOAT,
    DOLLARS_PER_CREDIT FLOAT
)
RETURNS OBJECT
AS
$$
  SELECT OBJECT_CONSTRUCT(
      'estimated_credits', RUNTIME_HOURS * CREDITS_PER_HOUR,
      'estimated_dollars', RUNTIME_HOURS * CREDITS_PER_HOUR * DOLLARS_PER_CREDIT
  )
$$;

-- 6. Verification queries (commented; run manually when needed)
-- SELECT SNOWFLAKE_EXAMPLE.FORECASTING.SFE_ESTIMATE_WH_COST(2, (SELECT PARAM_VALUE FROM SNOWFLAKE_EXAMPLE.FORECASTING.SFE_COST_PARAMS WHERE PARAM_NAME='SP_WH_LARGE_CREDITS_PER_HOUR'), (SELECT PARAM_VALUE FROM SNOWFLAKE_EXAMPLE.FORECASTING.SFE_COST_PARAMS WHERE PARAM_NAME='DOLLARS_PER_CREDIT'));

-- 7. Query tagging setup
-- Query tags enable cost attribution and workload analysis by labeling queries with metadata
-- Reference: https://docs.snowflake.com/en/sql-reference/parameters#query-tag
-- Format: WORKLOAD:{type}|PATH:{approach}
-- Examples:
--   ALTER SESSION SET QUERY_TAG = 'WORKLOAD:TRAINING|PATH:SNOWPARK_XGBOOST';
--   ALTER SESSION SET QUERY_TAG = 'WORKLOAD:INFERENCE|PATH:ML_FUNCTIONS';
--   ALTER SESSION SET QUERY_TAG = 'WORKLOAD:DATA_PREP';
-- Query tags are automatically captured in ACCOUNT_USAGE.QUERY_HISTORY for cost analysis

-- 8. Optional: Resource monitors for cost control
-- Resource monitors prevent runaway costs by setting credit quotas on warehouses
-- Uncomment and customize the following example to enable budget controls:
/*
CREATE RESOURCE MONITOR SFE_FORECASTING_MONITOR WITH
    CREDIT_QUOTA = 100  -- Maximum credits per month
    FREQUENCY = MONTHLY
    START_TIMESTAMP = IMMEDIATELY
    TRIGGERS
        ON 75 PERCENT DO NOTIFY  -- Alert at 75% usage
        ON 90 PERCENT DO SUSPEND  -- Suspend warehouse at 90% to prevent overages
        ON 100 PERCENT DO SUSPEND_IMMEDIATE;  -- Hard stop at 100%

ALTER WAREHOUSE SFE_SP_WH SET RESOURCE_MONITOR = SFE_FORECASTING_MONITOR;

-- View resource monitor status
-- SHOW RESOURCE MONITORS;
*/

-- 9. Warehouse permissions best practices
-- Grant USAGE to data scientists/analysts for query execution
-- Grant MONITOR for viewing warehouse metrics (no operational control)
-- Grant OPERATE to administrators only for scaling/suspension control
-- Example:
-- GRANT USAGE ON WAREHOUSE SFE_SP_WH TO ROLE DATA_SCIENTIST;
-- GRANT MONITOR ON WAREHOUSE SFE_SP_WH TO ROLE DATA_ANALYST;
