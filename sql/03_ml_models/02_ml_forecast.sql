/*******************************************************************************
 * DEMO PROJECT: Forecasting Lab
 * Script: Path 1 - Native ML Functions Forecasting
 * 
 * ⚠️  NOT FOR PRODUCTION USE - EXAMPLE IMPLEMENTATION ONLY
 * 
 * PURPOSE:
 *   Trains a time-series forecasting model using Snowflake's native
 *   SNOWFLAKE.ML.FORECAST function and generates 12-week forecasts.
 *   Pure SQL approach with no external dependencies.
 * 
 * OBJECTS CREATED:
 *   - SFE_GLOBAL_FORECAST_MODEL (ML.FORECAST model)
 *   - FORECAST_OUTPUT_GLOBAL_ML (Table - forecast results)
 *   - SFE_TASK_FORECAST_ML (Optional task for daily refresh)
 * 
 * QUERY TAGS:
 *   - WORKLOAD:TRAINING|PATH:ML_FUNCTIONS (model creation)
 *   - WORKLOAD:INFERENCE|PATH:ML_FUNCTIONS (forecast generation)
 * 
 * PREREQUISITES:
 *   - sql/01_setup/00_setup.sql completed
 *   - sql/02_transformations/01_synthetic_data.sql completed
 *   - FORECAST_INPUT_GLOBAL table populated
 * 
 * CLEANUP:
 *   See sql/99_cleanup/99_cleanup.sql
 ******************************************************************************/

-- SNOWFLAKE.ML.FORECAST path for Example forecasting modernization
-- Docs: https://docs.snowflake.com/en/user-guide/ml-functions/forecasting

-- Set query tag for cost attribution and workload monitoring
ALTER SESSION SET QUERY_TAG = 'WORKLOAD:TRAINING|PATH:ML_FUNCTIONS';

CREATE OR REPLACE SNOWFLAKE.ML.FORECAST SNOWFLAKE_EXAMPLE.FORECASTING.SFE_GLOBAL_FORECAST_MODEL(
    INPUT_DATA => TABLE(
        SELECT
            WEEK_ENDING,
            STREAMS
        FROM SNOWFLAKE_EXAMPLE.FORECASTING.FORECAST_INPUT_GLOBAL
        WHERE REGION = 'Global'
    ),
    TIMESTAMP_COLNAME => 'WEEK_ENDING',
    TARGET_COLNAME => 'STREAMS'
);

-- Switch to inference tag for forecasting queries
ALTER SESSION SET QUERY_TAG = 'WORKLOAD:INFERENCE|PATH:ML_FUNCTIONS';

-- Example inference
SELECT *
FROM TABLE(
  SNOWFLAKE_EXAMPLE.FORECASTING.SFE_GLOBAL_FORECAST_MODEL!FORECAST(
    FORECASTING_PERIODS => 12
  )
);

-- Persist results to output table
CREATE OR REPLACE TABLE SNOWFLAKE_EXAMPLE.FORECASTING.FORECAST_OUTPUT_GLOBAL_ML AS
SELECT *
FROM TABLE(
  SNOWFLAKE_EXAMPLE.FORECASTING.SFE_GLOBAL_FORECAST_MODEL!FORECAST(
    FORECASTING_PERIODS => 12
  )
);

-- Validate the output
SELECT * FROM SNOWFLAKE_EXAMPLE.FORECASTING.FORECAST_OUTPUT_GLOBAL_ML LIMIT 10;

-- Reset query tag
ALTER SESSION UNSET QUERY_TAG;

-- Optional: To schedule the forecast to run daily, uncomment the following section.
/*
-- Optional task to refresh forecasts daily using ML function
-- Note: Query tags for scheduled tasks should be set within the task SQL
CREATE OR REPLACE TASK SNOWFLAKE_EXAMPLE.FORECASTING.SFE_TASK_FORECAST_ML
  WAREHOUSE = SFE_SP_WH
  SCHEDULE = 'USING CRON 0 4 * * * America/Los_Angeles'
AS
  BEGIN
    ALTER SESSION SET QUERY_TAG = 'WORKLOAD:INFERENCE|PATH:ML_FUNCTIONS|SCHEDULED:TRUE';
    CREATE OR REPLACE TABLE SNOWFLAKE_EXAMPLE.FORECASTING.FORECAST_OUTPUT_GLOBAL_ML AS
    SELECT *
    FROM TABLE(
      SNOWFLAKE_EXAMPLE.FORECASTING.SFE_GLOBAL_FORECAST_MODEL!FORECAST(
        FORECASTING_PERIODS => 12
      )
    );
    ALTER SESSION UNSET QUERY_TAG;
  END;

ALTER TASK SNOWFLAKE_EXAMPLE.FORECASTING.SFE_TASK_FORECAST_ML RESUME;
*/
