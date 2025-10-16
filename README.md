# Snowflake Forecasting Lab

This repository provides a hands-on lab for two forecasting methods in Snowflake:

-   **Path 1: Native ML Functions** – Uses `SNOWFLAKE.ML.FORECAST` for a pure SQL-based approach.
-   **Path 2: Snowpark for Python** – Uses Python Stored Procedures for a custom modeling approach with XGBoost.

## Getting Started: Hands-On Lab

Follow these steps to set up your environment and run both forecasting paths.

### Initial Setup

Execute the following scripts from the `sql/` directory in your Snowflake worksheet. Run them in order.

1.  **`00_setup.sql`**: Creates the `SNOWFLAKE_EXAMPLE` database, `FORECASTING` schema, and a Snowpark-optimized warehouse (`SFE_SP_WH`).
2.  **`01_synthetic_data.sql`**: Creates and populates the `FORECAST_INPUT_GLOBAL` table with sample time-series data for the lab.

### Path 1: Native ML Functions (`SNOWFLAKE.ML.FORECAST`)

This path uses Snowflake's built-in forecasting capabilities.

3.  **`02_ml_forecast.sql`**:
    -   Creates a forecast model named `SFE_GLOBAL_FORECAST_MODEL`.
    -   Runs the model to generate a 12-week forecast and saves the results to the `FORECAST_OUTPUT_GLOBAL_ML` table.
    -   *(Optional)*: Contains a commented-out section to create a scheduled task (`SFE_TASK_FORECAST_ML`) to refresh the forecast daily.

### Path 2: Snowpark for Python (XGBoost)

This path demonstrates a more customizable approach using Python, Snowpark, and XGBoost in a stored procedure. Follow the official Snowflake Conda-based setup. You can run the helper script `python/03a_python_setup.sh`, or execute the commands manually:

```bash
bash python/03a_python_setup.sh
```
*(The script automatically sources `conda` so you do not need to run `conda init` manually.)*

```bash
# Create a Conda environment using the Snowflake channel
conda create -n snowpark_env --override-channels \
  -c https://repo.anaconda.com/pkgs/snowflake \
  python=3.12 numpy pandas pyarrow
conda activate snowpark_env

# Apple Silicon workaround from the docs
conda config --env --set subdir osx-64

# Install Snowflake packages
pip install snowflake-snowpark-python snowflake-ml-python

# Install remaining Python dependencies
pip install -r python/requirements.txt
```

This mirrors the guidance in the [Snowflake Snowpark setup documentation](https://docs.snowflake.com/developer-guide/snowpark/python/setup).

4.  **Run `python/03_snowpark_setup.py`**:
    -   *Note: This script relies on your local Snowflake credentials being configured (e.g., in `~/.snowflake/connections.toml` or via environment variables). It should be run from your local machine within the Conda environment you just created.*
    -   Connects to Snowflake and sets up the Feature Store and Model Registry.
    -   *(Optional)*: The script contains a commented-out section to create a scheduled task.

5.  **`sql/04_snowpark_training_inference.sql`**:
    -   Creates and deploys two stored procedures:
        -   `SFE_TRAIN_GLOBAL_MODEL`: Trains an XGBoost model.
        -   `SFE_FORECAST_GLOBAL`: Uses the trained model for inference.
    -   *(Optional)*: Contains a commented-out section to create tasks to run training and forecasting on a schedule.

### Cost Analysis and Monitoring

6.  **`sql/05_cost_analysis.sql`**: Demonstrates cost estimation using the cost estimator function and provides examples of query tag-based cost attribution. The estimation queries work without special privileges; attribution queries require `ACCOUNT_USAGE` access.

7.  **`sql/06_monitoring_queries.sql`**: Comprehensive monitoring queries for warehouse performance, cost attribution, query analysis, and efficiency metrics. Includes:
    - Warehouse utilization and queuing detection
    - Cost breakdown by workload type and model path
    - Query performance analysis
    - Warehouse efficiency metrics
    - Forecasting-specific insights
    - Optional resource monitor examples

### Interactive Monitoring Dashboard (Streamlit in Snowflake)

8.  **Streamlit Dashboard**: Deploy an interactive monitoring dashboard that runs natively in Snowflake:

**Deployment Steps:**

```sql
-- 1. Upload the dashboard file to Snowflake stage
-- Using Snowsight: Data > Databases > SNOWFLAKE_EXAMPLE > FORECASTING > Stages > SFE_STREAMLIT_STAGE
-- Upload: streamlit/monitoring/SFE_MONITORING_DASHBOARD.py

-- Or using SnowSQL:
PUT file://./streamlit/monitoring/SFE_MONITORING_DASHBOARD.py 
  @SNOWFLAKE_EXAMPLE.FORECASTING.SFE_STREAMLIT_STAGE 
  AUTO_COMPRESS=FALSE OVERWRITE=TRUE;

-- 2. Create the Streamlit app (run deploy_streamlit.sql or the command below)
CREATE OR REPLACE STREAMLIT SNOWFLAKE_EXAMPLE.FORECASTING.SFE_MONITORING_DASHBOARD
    ROOT_LOCATION = '@SNOWFLAKE_EXAMPLE.FORECASTING.SFE_STREAMLIT_STAGE'
    MAIN_FILE = 'SFE_MONITORING_DASHBOARD.py'
    QUERY_WAREHOUSE = 'SFE_SP_WH';

-- 3. Get the dashboard URL
SHOW STREAMLITS IN SCHEMA SNOWFLAKE_EXAMPLE.FORECASTING;
```

**Or access via Snowsight:** Projects → Streamlit → SFE_MONITORING_DASHBOARD

The dashboard provides:
- Warehouse performance metrics with queuing detection
- Interactive cost analytics and trends by workload type
- Query performance drill-down
- Automated optimization recommendations

**Benefits of Streamlit in Snowflake:**
- No local Python environment needed
- Uses your existing Snowflake authentication
- Easy sharing with team members through roles
- Runs on the warehouse you're already monitoring

See `streamlit/monitoring/README.md` for detailed deployment instructions.

### Cleanup

9.  **`sql/99_cleanup.sql`**: **Important!** Run this script to drop the `SNOWFLAKE_EXAMPLE` database and the `SFE_SP_WH` warehouse, removing all objects created during the lab. The script includes cost summary queries to review total expenses before cleanup.

## Repository Layout

-   `sql/`: Contains all the SQL scripts for the lab, organized by execution order.
-   `python/`: Contains helper Python code for the Snowpark path, including the Conda setup requirements.
-   `streamlit/`: Interactive dashboards for monitoring and visualization.
    -   `monitoring/`: Cost and performance monitoring dashboard with real-time analytics.
-   `docs/`: Additional documentation, including architecture and monitoring guide.
    -   `architecture.md`: System architecture and design overview
    -   `monitoring_guide.md`: Comprehensive monitoring and optimization guide
-   `data_quality/`: Placeholder for data quality checks.

## Monitoring and Cost Optimization

This lab includes enterprise-grade monitoring capabilities:

### Query Tagging
All forecasting workloads are automatically tagged for cost attribution:
- `WORKLOAD:TRAINING|PATH:ML_FUNCTIONS` - Training with ML Functions
- `WORKLOAD:INFERENCE|PATH:SNOWPARK_XGBOOST` - Inference with Snowpark
- `WORKLOAD:DATA_PREP` - Data preparation tasks

### Cost Attribution
Track costs by:
- Workload type (training vs inference vs data prep)
- Model path (ML Functions vs Snowpark XGBoost)
- Scheduled vs ad-hoc queries

### Performance Monitoring
- Warehouse utilization and queuing detection
- Query performance analysis
- Idle time tracking and optimization recommendations

### Best Practices
- **Warehouse Sizing**: Start with Medium, scale based on performance
- **Auto-Suspend**: 60-second timeout minimizes idle costs
- **Resource Monitors** (optional): Set credit quotas to prevent overruns
- **Query Optimization**: Monitor and optimize slow/expensive queries

For detailed monitoring instructions, see `docs/monitoring_guide.md`.
