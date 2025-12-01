# Data Flow - Snowflake Forecasting Lab

**Author:** SE Community  
**Last Updated:** 2025-11-24  
**Expires:** 2025-12-24 (30 days from creation)  
**Status:** Reference Implementation

![Snowflake](https://img.shields.io/badge/Snowflake-29B5E8?style=for-the-badge&logo=snowflake&logoColor=white)

**Reference Implementation:** This code demonstrates production-grade architectural patterns and best practices. Review and customize security, networking, and logic for your organization's specific requirements before deployment.

## Overview

This diagram shows how time-series streaming data flows through both forecasting paths: native ML Functions and Snowpark XGBoost. It illustrates data ingestion, feature engineering, model training, and inference stages.

## Diagram

```mermaid
graph TB
    subgraph "Data Generation"
        SynData[Synthetic Data Generator<br/>SQL GENERATOR function]
    end
    
    subgraph "Landing Zone - FORECASTING Schema"
        Input[(FORECAST_INPUT_GLOBAL<br/>Historical streaming data)]
    end
    
    subgraph "Path 1: ML Functions"
        MLModel[SNOWFLAKE.ML.FORECAST<br/>SFE_GLOBAL_FORECAST_MODEL]
        MLInfer[Model Inference<br/>model!FORECAST function]
        MLOutput[(FORECAST_OUTPUT_GLOBAL_ML<br/>Forecast results)]
        MLTask[SFE_TASK_FORECAST_ML<br/>Scheduled daily]
    end
    
    subgraph "Path 2: Snowpark XGBoost"
        FS[Feature Store<br/>SFE_STREAM_FEATURES]
        PySetup[Python Setup<br/>snowpark_setup.py]
        Train[Training Procedure<br/>SFE_TRAIN_GLOBAL_MODEL]
        ModelStage[@SFE_MODEL_STAGE<br/>XGBoost artifact]
        Registry[Model Registry<br/>SFE_STREAM_FORECAST_MODEL]
        Inference[Inference Procedure<br/>SFE_FORECAST_GLOBAL]
        SPOutput[(FORECAST_OUTPUT_GLOBAL<br/>Predictions + Actuals)]
        TrainTask[SFE_TASK_TRAIN_GLOBAL<br/>Weekly Sunday 2 AM]
        InferTask[SFE_TASK_FORECAST_GLOBAL<br/>Daily 3 AM]
    end
    
    subgraph "Monitoring & Analysis"
        Tags[Query Tags<br/>Cost Attribution]
        CostAnalysis[Cost Analysis Queries<br/>ACCOUNT_USAGE views]
        Dashboard[Streamlit Dashboard<br/>SFE_MONITORING_DASHBOARD]
    end
    
    SynData -->|INSERT| Input
    
    Input -->|"SELECT WHERE REGION='Global'"| MLModel
    MLModel -->|CREATE FORECAST| MLInfer
    MLInfer -->|CALL FORECAST| MLOutput
    MLTask -.->|Schedules| MLInfer
    
    Input -->|Feature extraction| FS
    FS -->|Register entity/view| PySetup
    Input -->|Training data| Train
    Train -->|XGBoost fit| ModelStage
    Train -->|Log model| Registry
    ModelStage -->|Load .pkl| Inference
    Inference -->|Predict| SPOutput
    TrainTask -.->|Weekly| Train
    InferTask -.->|Daily| Inference
    
    MLInfer -->|QUERY_TAG| Tags
    Train -->|QUERY_TAG| Tags
    Inference -->|QUERY_TAG| Tags
    Tags -->|Track costs| CostAnalysis
    CostAnalysis -->|Visualize| Dashboard
    
    style Input fill:#e1f5ff
    style MLOutput fill:#ffe1e1
    style SPOutput fill:#ffe1e1
    style MLModel fill:#d4edda
    style Train fill:#d4edda
    style Dashboard fill:#fff3cd
```

## Component Descriptions

### Data Generation

#### Synthetic Data Generator
- **Purpose:** Creates sample time-series data for lab exercises
- **Technology:** SQL `GENERATOR` table function with `UNIFORM` random distribution
- **Location:** `sql/02_transformations/01_synthetic_data.sql`
- **Output:** 312 rows (3 tracks × 52 weeks × 2 regions)
- **Pattern:** Upward trending streams with random variation (-20k to +20k per week)

### Landing Zone

#### FORECAST_INPUT_GLOBAL Table
- **Purpose:** Central repository for historical streaming data
- **Technology:** Snowflake permanent table
- **Location:** `SNOWFLAKE_EXAMPLE.FORECASTING.FORECAST_INPUT_GLOBAL`
- **Schema:** `(REGION, ISRC, DISPLAY_ARTIST, TRACK, RELEASE_DATE, WEEK_ENDING, STREAMS)`
- **Indexing:** Natural clustering on ingestion order
- **Refresh:** Full replacement via `DROP/CREATE TABLE` pattern

### Path 1: ML Functions Workflow

#### Training (Single SQL Statement)
```sql
CREATE OR REPLACE SNOWFLAKE.ML.FORECAST SFE_GLOBAL_FORECAST_MODEL(
    INPUT_DATA => TABLE(SELECT WEEK_ENDING, STREAMS FROM ...),
    TIMESTAMP_COLNAME => 'WEEK_ENDING',
    TARGET_COLNAME => 'STREAMS'
);
```
- **Algorithm:** Snowflake-managed (likely ARIMA/Prophet hybrid)
- **Training Time:** ~30-60 seconds on MEDIUM warehouse
- **Model Storage:** Internal Snowflake metadata
- **Cost:** Billed to `SFE_SP_WH` warehouse
- **Query Tag:** `WORKLOAD:TRAINING|PATH:ML_FUNCTIONS`

#### Inference
- **Method:** `model!FORECAST(FORECASTING_PERIODS => 12)` table function
- **Output:** 12-week forecast with confidence intervals
- **Execution:** On-demand or scheduled via `SFE_TASK_FORECAST_ML`
- **Cost:** Minimal compute (seconds of warehouse time)
- **Query Tag:** `WORKLOAD:INFERENCE|PATH:ML_FUNCTIONS`

#### Output Table
- **Purpose:** Materialized forecast results for consumption
- **Refresh Pattern:** `CREATE OR REPLACE TABLE ... AS SELECT * FROM model!FORECAST()`
- **Consumers:** BI dashboards, downstream analytics

### Path 2: Snowpark XGBoost Workflow

#### Setup Phase (One-Time)
1. **Python Environment:** Conda environment with Snowflake channels
2. **Feature Store Registration:** Creates `SFE_TRACK` entity and `SFE_STREAM_FEATURES` view
3. **Model Registry Setup:** Initializes registry schema

#### Feature Engineering
- **Implementation:** Snowpark DataFrame API with window functions
- **Features Generated:**
  - `WEEK_SINCE_RELEASE`: Days since track release / 7
  - `WEEK_SINCE_RELEASE_SQ`, `WEEK_SINCE_RELEASE_CB`: Polynomial features
  - `WEEK_OF_YEAR`: Seasonality feature
  - `IS_FIRST_4_WEEKS`: Binary indicator for launch period
  - `LAST_WEEK_STREAMS`: Lag-1 feature
  - `AVG_STREAMS_TO_DATE`: Cumulative rolling average
  - `PCT_CHANGE`: Week-over-week growth rate
  - `LOG_STREAMS`: Log-transformed target (reduces skew)

#### Training (SFE_TRAIN_GLOBAL_MODEL Stored Procedure)
```python
model = XGBRegressor(
    n_estimators=300,
    max_depth=7,
    learning_rate=0.03,
    subsample=0.8,
    colsample_bytree=0.8,
    objective='reg:squarederror'
)
model.fit(X, y)
```
- **Execution:** Snowpark-optimized warehouse (`SFE_SP_WH`)
- **Training Time:** ~2-5 minutes on MEDIUM warehouse
- **Model Artifact:** Serialized to `@SFE_MODEL_STAGE/SFE_MODEL_GLOBAL_XGB_FULL.pkl`
- **Registry:** Logged as `SFE_STREAM_FORECAST_MODEL` version `v1`
- **Query Tag:** `WORKLOAD:TRAINING|PATH:SNOWPARK_XGBOOST`
- **Schedule:** Weekly (Sundays 2 AM PT via `SFE_TASK_TRAIN_GLOBAL`)

#### Inference (SFE_FORECAST_GLOBAL Stored Procedure)
- **Input:** `REGION` parameter (e.g., 'Global' or 'US')
- **Process:**
  1. Load model from stage: `joblib.load('/tmp/SFE_MODEL_GLOBAL_XGB_FULL.pkl')`
  2. Build features for target region using Snowpark DataFrame
  3. Batch predict using XGBoost
  4. Transform predictions: `STREAMS_PREDICTED = np.expm1(log_predictions)`
  5. Write to output table with `COPY GRANTS` pattern
- **Query Tag:** `WORKLOAD:INFERENCE|PATH:SNOWPARK_XGBOOST`
- **Schedule:** Daily (3 AM PT via `SFE_TASK_FORECAST_GLOBAL`)
- **Output:** Combined actual + predicted values with `IS_FORECAST` flag

### Monitoring & Cost Attribution

#### Query Tagging Strategy
All forecasting workloads tagged with structured metadata:
```sql
ALTER SESSION SET QUERY_TAG = 'WORKLOAD:{type}|PATH:{approach}';
```
- **Workload Types:** `TRAINING`, `INFERENCE`, `DATA_PREP`
- **Paths:** `ML_FUNCTIONS`, `SNOWPARK_XGBOOST`
- **Scheduled Indicator:** `SCHEDULED:TRUE` for automated tasks

#### Cost Analysis
- **Pre-Execution:** `SFE_ESTIMATE_WH_COST(runtime, credits_per_hour, dollars_per_credit)` function
- **Post-Execution:** Queries against `SNOWFLAKE.ACCOUNT_USAGE.QUERY_HISTORY` and `WAREHOUSE_METERING_HISTORY`
- **Attribution Dimensions:**
  - Workload type (training vs inference vs data prep)
  - Model path (ML Functions vs Snowpark)
  - Scheduled vs ad-hoc queries

#### Streamlit Dashboard
- **Purpose:** Interactive monitoring and cost analytics
- **Technology:** Streamlit in Snowflake (native hosting)
- **Features:**
  - Warehouse performance metrics with queuing detection
  - Cost trends by workload type
  - Query performance drill-down
  - Automated optimization recommendations
- **Access:** Via Snowsight UI or direct URL

## Data Lineage Summary

| Stage | Input | Transformation | Output | Technology |
|-------|-------|----------------|--------|------------|
| **Generation** | SQL generator | `UNIFORM()` random distribution | `FORECAST_INPUT_GLOBAL` | SQL |
| **ML Functions** | `FORECAST_INPUT_GLOBAL` | `SNOWFLAKE.ML.FORECAST` | `SFE_GLOBAL_FORECAST_MODEL` | Native SQL |
| **ML Inference** | `SFE_GLOBAL_FORECAST_MODEL` | `model!FORECAST(12)` | `FORECAST_OUTPUT_GLOBAL_ML` | Native SQL |
| **Feature Store** | `FORECAST_INPUT_GLOBAL` | Snowpark window functions | `SFE_STREAM_FEATURES` | Python + Snowpark |
| **Snowpark Training** | `FORECAST_INPUT_GLOBAL` | XGBoost regression | `SFE_MODEL_GLOBAL_XGB_FULL.pkl` | Python + XGBoost |
| **Snowpark Inference** | Model + Input | XGBoost predict | `FORECAST_OUTPUT_GLOBAL` | Python + Snowpark |

## Data Retention

- **Input Data:** Permanent table (retained until cleanup)
- **ML Functions Model:** Persisted as Snowflake object until dropped
- **Snowpark Model Artifact:** Persisted in stage until cleanup
- **Output Tables:** Overwritten on each refresh (no history)
- **Query History:** 365 days in `ACCOUNT_USAGE`
- **Cost Metrics:** 365 days in `ACCOUNT_USAGE`

## Change History

See `.cursor/DIAGRAM_CHANGELOG.md` for version history.



