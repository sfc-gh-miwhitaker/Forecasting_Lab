-- Cleanup script for Example forecasting modernization
-- Drops the database and warehouse to remove all lab-related objects.

DROP DATABASE IF EXISTS SNOWFLAKE_EXAMPLE;
DROP WAREHOUSE IF EXISTS SFE_SP_WH;