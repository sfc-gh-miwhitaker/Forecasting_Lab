# Forecasting Lab Monitoring Dashboard (Streamlit in Snowflake)

Interactive Streamlit dashboard running natively in Snowflake for monitoring forecasting workload performance and costs.

## Overview

This dashboard runs as a **Streamlit in Snowflake** application, which means:
- ✅ No local Python environment needed
- ✅ No credential management required (uses your Snowflake session)
- ✅ Accessible from any web browser via Snowflake
- ✅ Easy sharing with team members through Snowflake roles
- ✅ Runs on the same warehouse you're monitoring

## Deployment Steps

### 1. Ensure Setup is Complete

Make sure you've run `sql/00_setup.sql` which creates the necessary stage:

```sql
-- This should already exist from 00_setup.sql
CREATE STAGE IF NOT EXISTS SNOWFLAKE_EXAMPLE.FORECASTING.SFE_STREAMLIT_STAGE;
```

### 2. Upload the Streamlit Application

**Option A: Using Snowsight (Web UI)**

1. Open Snowsight and navigate to:
   - **Data** → **Databases** → **SNOWFLAKE_EXAMPLE** → **FORECASTING** → **Stages**
2. Click on `SFE_STREAMLIT_STAGE`
3. Click **+ Files** (top right)
4. Upload `SFE_MONITORING_DASHBOARD.py` from this directory
5. Verify the file appears in the stage

**Option B: Using SnowSQL (Command Line)**

```bash
# From the project root directory
snowsql -c <your_connection>

# Upload the file
PUT file://./streamlit/monitoring/SFE_MONITORING_DASHBOARD.py 
  @SNOWFLAKE_EXAMPLE.FORECASTING.SFE_STREAMLIT_STAGE 
  AUTO_COMPRESS=FALSE 
  OVERWRITE=TRUE;
```

**Option C: Using Python**

```python
from snowflake.snowpark import Session

# Create session (use your connection method)
session = Session.builder.configs({...}).create()

# Upload file
session.file.put(
    "streamlit/monitoring/SFE_MONITORING_DASHBOARD.py",
    "@SNOWFLAKE_EXAMPLE.FORECASTING.SFE_STREAMLIT_STAGE",
    auto_compress=False,
    overwrite=True
)
```

### 3. Deploy the Streamlit App

Run the deployment script in a Snowflake worksheet:

```sql
-- Execute this SQL script
@streamlit/monitoring/deploy_streamlit.sql
```

Or run directly:

```sql
USE DATABASE SNOWFLAKE_EXAMPLE;
USE SCHEMA FORECASTING;
USE WAREHOUSE SFE_SP_WH;

CREATE OR REPLACE STREAMLIT SNOWFLAKE_EXAMPLE.FORECASTING.SFE_MONITORING_DASHBOARD
    ROOT_LOCATION = '@SNOWFLAKE_EXAMPLE.FORECASTING.SFE_STREAMLIT_STAGE'
    MAIN_FILE = 'SFE_MONITORING_DASHBOARD.py'
    QUERY_WAREHOUSE = 'SFE_SP_WH'
    COMMENT = 'Cost and Performance Monitoring Dashboard for Forecasting Lab';
```

### 4. Access the Dashboard

After deployment, get the dashboard URL:

```sql
SHOW STREAMLITS IN SCHEMA SNOWFLAKE_EXAMPLE.FORECASTING;
```

Or in Snowsight:
1. Navigate to **Projects** → **Streamlit**
2. Find `SFE_MONITORING_DASHBOARD`
3. Click to open

## Dashboard Features

### Tab 1: Warehouse Performance
- Total credits and cost summary for the selected time window
- Hourly credit consumption line chart
- Warehouse load visualization (running vs queued queries)
- Automatic alerts for performance issues

### Tab 2: Cost Analytics
- Pie chart: Cost distribution by workload type
- Bar chart: ML Functions vs Snowpark XGBoost comparison
- Area chart: Daily spending trends
- Projections: Average, peak, and monthly cost estimates
- Detailed cost breakdown table

### Tab 3: Query Analysis
- Bar chart: Top 10 slowest queries
- Performance statistics grouped by workload type
- Histogram: Execution time distribution
- Queue time analysis with warnings for delayed queries

### Tab 4: Recommendations
- Automated issue detection with priority levels (HIGH/MEDIUM/LOW)
- Categories: Performance, Cost, Monitoring
- Actionable SQL commands for immediate fixes
- Best practices summary

## Configuration

### Time Windows
Select from the sidebar:
- Last 7 days (default)
- Last 14 days
- Last 30 days

### Cost Parameters
The dashboard automatically reads from `SFE_COST_PARAMS` table. Update costs:

```sql
UPDATE SNOWFLAKE_EXAMPLE.FORECASTING.SFE_COST_PARAMS
SET param_value = 3.50  -- Your actual cost per credit
WHERE param_name = 'DOLLARS_PER_CREDIT';
```

## Permissions

### To View the Dashboard

Users need:
```sql
GRANT USAGE ON DATABASE SNOWFLAKE_EXAMPLE TO ROLE <role_name>;
GRANT USAGE ON SCHEMA SNOWFLAKE_EXAMPLE.FORECASTING TO ROLE <role_name>;
GRANT USAGE ON STREAMLIT SNOWFLAKE_EXAMPLE.FORECASTING.SFE_MONITORING_DASHBOARD TO ROLE <role_name>;
GRANT USAGE ON WAREHOUSE SFE_SP_WH TO ROLE <role_name>;
```

### For ACCOUNT_USAGE Data

Users need access to monitoring views:
```sql
-- Grant by ACCOUNTADMIN
GRANT IMPORTED PRIVILEGES ON DATABASE SNOWFLAKE TO ROLE <role_name>;
```

## Troubleshooting

### Issue: Dashboard shows no data

**Possible Causes:**
1. No forecasting workloads have run yet
2. ACCOUNT_USAGE data hasn't populated (wait up to 45 minutes)
3. User lacks ACCOUNT_USAGE permissions

**Solution:**
```sql
-- Check if you have access
SELECT COUNT(*) FROM SNOWFLAKE.ACCOUNT_USAGE.QUERY_HISTORY 
WHERE warehouse_name = 'SFE_SP_WH';
```

### Issue: Streamlit app won't create

**Check:**
1. Verify file uploaded to stage:
   ```sql
   LIST @SNOWFLAKE_EXAMPLE.FORECASTING.SFE_STREAMLIT_STAGE;
   ```
2. Verify you have CREATE STREAMLIT privilege
3. Check warehouse is running

### Issue: Permission denied

**Solution:**
```sql
-- View your current role and permissions
SELECT CURRENT_ROLE();

-- Switch to a role with appropriate permissions
USE ROLE ACCOUNTADMIN;  -- or appropriate role
```

## Updating the Dashboard

To update the dashboard after making changes:

1. Upload the new version of `SFE_MONITORING_DASHBOARD.py` to the stage
2. The Streamlit app will automatically use the updated file
3. Refresh your browser to see changes

## Cleanup

To remove the dashboard:

```sql
DROP STREAMLIT IF EXISTS SNOWFLAKE_EXAMPLE.FORECASTING.SFE_MONITORING_DASHBOARD;
DROP STAGE IF EXISTS SNOWFLAKE_EXAMPLE.FORECASTING.SFE_STREAMLIT_STAGE;
```

This is included in `sql/99_cleanup.sql`.

## Advanced Usage

### Custom Queries

To add custom metrics, edit `SFE_MONITORING_DASHBOARD.py` and add new functions that query your data.

### Scheduled Refresh

The dashboard automatically refreshes data every 5 minutes (cached). Users can also manually refresh by interacting with the sidebar.

### Sharing

Share the dashboard URL with team members who have appropriate Snowflake access. No additional setup required on their end.

## Documentation

For more details:
- **Complete Monitoring Guide**: `../../docs/monitoring_guide.md`
- **SQL Monitoring Queries**: `../../sql/06_monitoring_queries.sql`
- **Architecture Overview**: `../../docs/architecture.md`

## Support

For issues specific to Streamlit in Snowflake, consult:
- [Streamlit in Snowflake Documentation](https://docs.snowflake.com/en/developer-guide/streamlit/about-streamlit)
- [Snowflake Support](https://community.snowflake.com/)
