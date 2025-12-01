# Snowflake Forecasting Lab

![Reference Implementation](https://img.shields.io/badge/Reference-Implementation-blue)
![Ready to Run](https://img.shields.io/badge/Ready%20to%20Run-Yes-green)
![Expires](https://img.shields.io/badge/Expires-2025--12--24-orange)

> ⚠️ **DEMONSTRATION PROJECT - EXPIRES: 2025-12-24**  
> This demo uses Snowflake features current as of November 2025.  
> After expiration, this repository will be archived and made private.

**Author:** SE Community  
**Purpose:** Reference implementation for time-series forecasting comparison (ML Functions vs Snowpark XGBoost)  
**Created:** 2025-11-24 | **Expires:** 2025-12-24 (30 days) | **Status:** ACTIVE

---

## 👋 First Time Here?

Follow these guides in order:

1. **`sql/01_setup/00_setup.sql`** - Create database, schema, and warehouse (5 min)
2. **`sql/02_transformations/01_synthetic_data.sql`** - Generate sample time-series data (2 min)
3. **Choose Your Forecasting Path:**
   - **Path 1 (Easier):** `sql/03_ml_models/02_ml_forecast.sql` - Native ML Functions (5 min)
   - **Path 2 (Advanced):** Follow Snowpark setup below (15 min)
4. **`sql/04_monitoring/05_cost_analysis.sql`** - Review cost estimation (5 min)
5. **`sql/04_monitoring/06_monitoring_queries.sql`** - Explore performance metrics (5 min)
6. **`streamlit/monitoring/README.md`** - Deploy interactive dashboard (Optional, 10 min)
7. **`sql/99_cleanup/99_cleanup.sql`** - Cleanup when done (1 min)

**Total setup time:** ~20-30 minutes (depending on path)

---

## Overview

This repository provides a hands-on lab for two forecasting methods in Snowflake:

-   **Path 1: Native ML Functions** – Uses `SNOWFLAKE.ML.FORECAST` for a pure SQL-based approach.
-   **Path 2: Snowpark for Python** – Uses Python Stored Procedures for a custom modeling approach with XGBoost.

## Architecture Diagrams

📊 **View complete system architecture:**
- **[Data Model](diagrams/data-model.md)** - Database schema and relationships
- **[Data Flow](diagrams/data-flow.md)** - How data moves through both forecasting paths
- **[Network Flow](diagrams/network-flow.md)** - Snowflake architecture and connectivity
- **[Auth Flow](diagrams/auth-flow.md)** - Authentication and authorization patterns

## Path 1: Native ML Functions (`SNOWFLAKE.ML.FORECAST`)

This path uses Snowflake's built-in forecasting capabilities.

**Steps:**
1. Run `sql/01_setup/00_setup.sql` - Creates database and warehouse
2. Run `sql/02_transformations/01_synthetic_data.sql` - Generates sample data
3. Run `sql/03_ml_models/02_ml_forecast.sql` - Trains model and generates forecast

**What This Does:**
-   Creates a forecast model named `SFE_GLOBAL_FORECAST_MODEL`.
-   Runs the model to generate a 12-week forecast and saves the results to the `FORECAST_OUTPUT_GLOBAL_ML` table.
-   *(Optional)*: Contains a commented-out section to create a scheduled task (`SFE_TASK_FORECAST_ML`) to refresh the forecast daily.

**Time:** ~10 minutes total

---

## Path 2: Snowpark for Python (XGBoost)

This path demonstrates a more customizable approach using Python, Snowpark, and XGBoost in a stored procedure.

### Prerequisites: Conda Environment Setup

Follow the official Snowflake Conda-based setup. You can run the helper script or execute the commands manually:

**Option A: Automated Setup (Recommended)**
```bash
bash python/setup_conda_env.sh
```
*(The script automatically sources `conda` so you do not need to run `conda init` manually.)*

**Option B: Manual Setup**
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

### Snowpark Path Steps

1. **Setup database and data** (if not done already):
   - Run `sql/01_setup/00_setup.sql`
   - Run `sql/02_transformations/01_synthetic_data.sql`

2. **Run `python/snowpark_setup.py`**:
    -   *Note: This script relies on your local Snowflake credentials being configured (e.g., in `~/.snowflake/connections.toml` or via environment variables). It should be run from your local machine within the Conda environment you just created.*
    -   Connects to Snowflake and sets up the Feature Store and Model Registry.
    -   *(Optional)*: The script contains a commented-out section to create a scheduled task.

3. **Run `sql/03_ml_models/04_snowpark_training_inference.sql`**:
    -   Creates and deploys two stored procedures:
        -   `SFE_TRAIN_GLOBAL_MODEL`: Trains an XGBoost model.
        -   `SFE_FORECAST_GLOBAL`: Uses the trained model for inference.
    -   *(Optional)*: Contains a commented-out section to create tasks to run training and forecasting on a schedule.

**Time:** ~15-20 minutes total

---

## Cost Analysis and Monitoring

### Cost Estimation

**6. `sql/04_monitoring/05_cost_analysis.sql`**

Demonstrates cost estimation using the cost estimator function and provides examples of query tag-based cost attribution. The estimation queries work without special privileges; attribution queries require `ACCOUNT_USAGE` access.

### Performance Monitoring

**7. `sql/04_monitoring/06_monitoring_queries.sql`**

Comprehensive monitoring queries for warehouse performance, cost attribution, query analysis, and efficiency metrics. Includes:
- Warehouse utilization and queuing detection
- Cost breakdown by workload type and model path
- Query performance analysis
- Warehouse efficiency metrics
- Forecasting-specific insights
- Optional resource monitor examples

### Interactive Monitoring Dashboard (Streamlit in Snowflake)

**8. Streamlit Dashboard**

Deploy an interactive monitoring dashboard that runs natively in Snowflake:

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

---

## Cleanup

**9. `sql/99_cleanup/99_cleanup.sql`**

**Important!** Run this script to drop the `SNOWFLAKE_EXAMPLE` database and the `SFE_SP_WH` warehouse, removing all objects created during the lab. The script includes cost summary queries to review total expenses before cleanup.

---

## Repository Layout

-   **`sql/`**: Contains all the SQL scripts for the lab, organized by execution order.
    -   `01_setup/` - Database and warehouse creation
    -   `02_transformations/` - Data generation
    -   `03_ml_models/` - Both forecasting paths
    -   `04_monitoring/` - Cost analysis and performance queries
    -   `99_cleanup/` - Teardown scripts
-   **`python/`**: Contains helper Python code for the Snowpark path, including the Conda setup requirements.
    -   `snowpark_setup.py` - Feature Store and Model Registry setup
    -   `setup_conda_env.sh` - Automated Conda environment creation
    -   `requirements.txt` - Python dependencies
-   **`streamlit/`**: Interactive dashboards for monitoring and visualization.
    -   `monitoring/` - Cost and performance monitoring dashboard with real-time analytics.
-   **`diagrams/`**: Architecture diagrams (data model, data flow, network flow, auth flow).
-   **`docs/`**: Additional documentation, including architecture and monitoring guide.
    -   `01-ARCHITECTURE.md` - System architecture and design overview
    -   `02-MONITORING.md` - Comprehensive monitoring and optimization guide
    -   `03-COST-COMPARISON.md` - Cost analysis between approaches

---

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

For detailed monitoring instructions, see `docs/02-MONITORING.md`.

---

## Objects Created by This Demo

### Account-Level Objects (Require ACCOUNTADMIN)
| Object Type | Name | Purpose |
|-------------|------|---------|
| Warehouse | `SFE_SP_WH` | Snowpark-Optimized MEDIUM warehouse for all workloads |

### Database Objects (in SNOWFLAKE_EXAMPLE)
| Object Type | Schema | Name | Purpose |
|-------------|--------|------|---------|
| Database | - | `SNOWFLAKE_EXAMPLE` | Container for all demo objects |
| Schema | - | `FORECASTING` | All forecasting tables and procedures |
| Table | `FORECASTING` | `FORECAST_INPUT_GLOBAL` | Historical streaming data (input) |
| Table | `FORECASTING` | `FORECAST_OUTPUT_GLOBAL_ML` | ML Functions forecast results |
| Table | `FORECASTING` | `FORECAST_OUTPUT_GLOBAL` | Snowpark XGBoost results |
| Table | `FORECASTING` | `SFE_COST_PARAMS` | Cost estimation parameters |
| Stage | `FORECASTING` | `SFE_MODEL_STAGE` | XGBoost model artifact storage |
| Stage | `FORECASTING` | `SFE_STREAMLIT_STAGE` | Streamlit dashboard files |
| Model | `FORECASTING` | `SFE_GLOBAL_FORECAST_MODEL` | ML Functions forecast model |
| Feature Store | `FORECASTING` | `SFE_FEATURE_STORE` | Feature engineering catalog |
| Model Registry | `FORECASTING` | `SFE_STREAM_FORECAST_MODEL` | XGBoost model metadata |
| Procedure | `FORECASTING` | `SFE_TRAIN_GLOBAL_MODEL()` | XGBoost training procedure |
| Procedure | `FORECASTING` | `SFE_FORECAST_GLOBAL(REGION)` | XGBoost inference procedure |
| Streamlit | `FORECASTING` | `SFE_MONITORING_DASHBOARD` | Interactive monitoring dashboard |

---

## Complete Cleanup

Remove all demo artifacts:

```sql
-- Run this script to remove everything:
-- sql/99_cleanup/99_cleanup.sql

-- Or manually:
DROP DATABASE IF EXISTS SNOWFLAKE_EXAMPLE CASCADE;
DROP WAREHOUSE IF EXISTS SFE_SP_WH;
```

**Time:** < 1 minute  
**Verification:** Run `SHOW DATABASES LIKE 'SNOWFLAKE_EXAMPLE'` - should return no results

---

## Troubleshooting

### Common Issues

**Issue:** "Insufficient privileges to create warehouse"  
**Solution:** Ensure you are using `ACCOUNTADMIN` role or have `CREATE WAREHOUSE` privilege

**Issue:** "Conda environment activation fails"  
**Solution:** Run `conda init` and restart your terminal, or use the automated script

**Issue:** "Python script can't connect to Snowflake"  
**Solution:** Verify `~/.snowflake/connections.toml` exists with correct credentials

**Issue:** "XGBoost training procedure fails"  
**Solution:** Verify warehouse `SFE_SP_WH` is running and is Snowpark-Optimized

For more troubleshooting, see `docs/02-MONITORING.md`.

---

## License

This is a demonstration project for educational purposes. See [LICENSE](LICENSE) for details.
