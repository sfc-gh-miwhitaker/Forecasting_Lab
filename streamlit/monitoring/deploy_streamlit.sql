-- Deploy Streamlit in Snowflake for Forecasting Lab Monitoring Dashboard
-- This script creates a Streamlit app that runs natively in your Snowflake account

USE DATABASE SNOWFLAKE_EXAMPLE;
USE SCHEMA FORECASTING;
USE WAREHOUSE SFE_SP_WH;

-- Create the Streamlit app
CREATE OR REPLACE STREAMLIT SNOWFLAKE_EXAMPLE.FORECASTING.SFE_MONITORING_DASHBOARD
    ROOT_LOCATION = '@SNOWFLAKE_EXAMPLE.FORECASTING.SFE_STREAMLIT_STAGE'
    MAIN_FILE = 'SFE_MONITORING_DASHBOARD.py'
    QUERY_WAREHOUSE = 'SFE_SP_WH'
    COMMENT = 'Cost and Performance Monitoring Dashboard for Forecasting Lab';

-- Grant usage to appropriate roles (adjust as needed)
-- GRANT USAGE ON STREAMLIT SNOWFLAKE_EXAMPLE.FORECASTING.SFE_MONITORING_DASHBOARD TO ROLE DATA_ANALYST;

-- To view the app URL
SHOW STREAMLITS IN SCHEMA SNOWFLAKE_EXAMPLE.FORECASTING;

-- Note: After running this script, upload SFE_MONITORING_DASHBOARD.py to the stage:
-- 1. In Snowsight, navigate to Data > Databases > SNOWFLAKE_EXAMPLE > FORECASTING > Stages
-- 2. Click on SFE_STREAMLIT_STAGE
-- 3. Upload SFE_MONITORING_DASHBOARD.py
-- 
-- Or use SnowSQL:
-- PUT file://./streamlit/monitoring/SFE_MONITORING_DASHBOARD.py @SNOWFLAKE_EXAMPLE.FORECASTING.SFE_STREAMLIT_STAGE AUTO_COMPRESS=FALSE OVERWRITE=TRUE;

