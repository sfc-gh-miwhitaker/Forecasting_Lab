# Architecture Overview

This document explains how the modernized Example forecasting solution is organized across Snowflake components. Both deployment paths share the same data model and ML assets; they differ only in how compute is provisioned.

## Core Snowflake Objects (SFE-prefixed)

- `SFE_SP_WH` – Snowpark-optimized warehouse for stored procedure execution, feature store refresh, and scheduled tasks.
- `SFE_MODEL_STAGE` – External/internal stage that holds serialized model artifacts (`SFE_MODEL_GLOBAL_XGB_FULL.pkl`).
- `SFE_FEATURE_STORE` – Feature Store catalog for reusable feature views.
- `SFE_TRACK` – Feature Store entity keyed by `ISRC`.
- `SFE_STREAM_FEATURES` – Feature view deriving rolling metrics from `SNOWFLAKE_EXAMPLE.FORECASTING.FORECAST_INPUT_GLOBAL`.
- `SFE_STREAM_FORECAST_MODEL` – Model Registry entry storing the trained XGBoost model with version aliases.
- `SFE_TASK_*` – Scheduled Snowflake tasks for training, inference, and feature refresh.
- `SFE_COST_PARAMS`, `SFE_ESTIMATE_WH_COST` – Cost estimation helpers.

## Path 1: Snowpark-Optimized Warehouse

1. `SFE_TRAIN_GLOBAL_MODEL` stored procedure trains the model using Snowpark pandas feature engineering and XGBoost.
2. `SFE_FORECAST_GLOBAL` stored procedure scores observations and writes to `SNOWFLAKE_EXAMPLE.FORECASTING.FORECAST_OUTPUT_GLOBAL` using COPY GRANTS.
3. Tasks `SFE_TASK_TRAIN_GLOBAL` and `SFE_TASK_FORECAST_GLOBAL` orchestrate weekly training and daily inference.
4. Cost estimates use warehouse credit rates before runtime; post-run validation queries inspect `ORGANIZATION_USAGE.WAREHOUSE_METERING_HISTORY`.

## Path 2: SNOWFLAKE.ML.FORECAST

1. `SFE_GLOBAL_FORECAST_MODEL` is created via `SNOWFLAKE.ML.FORECAST` with the global weekly streams as input.
2. `FORECAST_OUTPUT_GLOBAL_ML` persists results from `model!FORECAST()`.
3. `SFE_TASK_FORECAST_ML` (optional) refreshes the ML forecast daily using the Snowpark-optimized warehouse.
4. This path removes dependency on external Python packages and keeps modeling inside native Snowflake ML functions.

## Feature Store & Model Registry Flow

1. Feature engineering logic is registered in the Feature Store so future workloads can reuse the same transformations.
2. After each training cycle the stored procedure saves a model artifact and updates the Model Registry (versioned, aliasable).
3. Downstream consumers can fetch features via the Feature Store or call the registered model for batch inference.

## Data Quality & Scheduling

- `data_quality/` contains placeholders for integrity checks (nulls, duplicates, business rules) that can be extended.
- Scheduling scripts live in `config/` to cleanly separate operational automation from core logic.

## Cost & Performance Monitoring

The lab includes comprehensive monitoring capabilities for tracking warehouse performance and attributing costs:

### Query Tagging Strategy

All forecasting workloads are tagged with structured metadata for cost attribution:

```sql
WORKLOAD:{type}|PATH:{approach}
```

- **Workload Types**: `TRAINING`, `INFERENCE`, `DATA_PREP`
- **Model Paths**: `ML_FUNCTIONS`, `SNOWPARK_XGBOOST`

This enables granular cost analysis by workload type and forecasting approach.

### Monitoring Components

1. **SQL Monitoring Queries** (`sql/06_monitoring_queries.sql`):
   - Warehouse utilization and load history (queuing detection)
   - Cost attribution by query tag
   - Query performance analysis
   - Warehouse efficiency metrics (idle time)
   - Forecasting workload insights
   - Optional automated resource monitor examples

2. **Streamlit in Snowflake Dashboard** (`streamlit/monitoring/`):
   - Interactive visualizations of warehouse performance
   - Real-time cost analytics with trend analysis
   - Query performance drill-down
   - Automated optimization recommendations
   - Runs natively in Snowflake (no local setup required)

3. **Cost Analysis** (`sql/05_cost_analysis.sql`):
   - Pre-execution cost estimation using warehouse parameters
   - Post-execution cost attribution using query tags
   - Path comparison (ML Functions vs Snowpark XGBoost)

### Warehouse Optimization Best Practices

The lab implements several cost and performance optimization strategies:

- **Auto-Suspend**: 60-second timeout to minimize idle compute costs
- **Query Tags**: Automatic tagging for all workloads enables cost attribution
- **Resource Monitors** (optional): Credit quotas with progressive alerts
- **Warehouse Sizing**: Starts with Medium, scales based on actual performance needs
- **Scheduled Tasks**: Optimized timing to avoid conflicts and minimize costs

### Monitoring Workflow

1. **Setup**: Query tags are automatically applied in all SQL scripts and Python procedures
2. **Execution**: Workloads run with tags captured in `ACCOUNT_USAGE.QUERY_HISTORY`
3. **Analysis**: Run monitoring queries or launch Streamlit dashboard
4. **Optimization**: Apply recommendations from automated analysis
5. **Iteration**: Continuously refine based on actual usage patterns

See `docs/monitoring_guide.md` for detailed monitoring instructions and troubleshooting.

## Cleanup Strategy

Cleanup SQL scripts drop tasks, stored procedures, feature store objects, model registry entries, resource monitors, and cost helper objects. The cleanup script includes cost summary queries to review total lab expenses before removal. Always suspend tasks before dropping warehouses.
