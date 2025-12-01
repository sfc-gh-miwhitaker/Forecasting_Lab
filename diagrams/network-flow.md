# Network Flow - Snowflake Forecasting Lab

**Author:** SE Community  
**Last Updated:** 2025-11-24  
**Expires:** 2025-12-24 (30 days from creation)  
**Status:** Reference Implementation

![Snowflake](https://img.shields.io/badge/Snowflake-29B5E8?style=for-the-badge&logo=snowflake&logoColor=white)

**Reference Implementation:** This code demonstrates production-grade architectural patterns and best practices. Review and customize security, networking, and logic for your organization's specific requirements before deployment.

## Overview

This diagram shows the network architecture and component connectivity for the forecasting lab, including client connections, Snowflake virtual warehouses, compute layers, and external integrations.

## Diagram

```mermaid
graph TB
    subgraph "Client Layer"
        Snowsight[Snowsight Web UI<br/>HTTPS :443]
        Python[Python Client<br/>snowpark-python SDK]
        SnowSQL[SnowSQL CLI<br/>Command Line]
    end
    
    subgraph "Snowflake Account<br/>account.snowflakecomputing.com"
        
        subgraph "Query Processing"
            CloudServices[Cloud Services Layer<br/>Query optimization, metadata]
        end
        
        subgraph "Virtual Warehouses"
            SFEWH[SFE_SP_WH<br/>Snowpark-Optimized MEDIUM<br/>Auto-suspend: 60s]
        end
        
        subgraph "Storage Layer"
            DB[(SNOWFLAKE_EXAMPLE<br/>Database)]
            
            subgraph "Schemas"
                Schema[FORECASTING<br/>Schema]
            end
            
            subgraph "Tables"
                InputTable[FORECAST_INPUT_GLOBAL]
                OutputML[FORECAST_OUTPUT_GLOBAL_ML]
                OutputSP[FORECAST_OUTPUT_GLOBAL]
                CostParams[SFE_COST_PARAMS]
            end
            
            subgraph "Stages"
                ModelStage[@SFE_MODEL_STAGE<br/>Model artifacts]
                StreamlitStage[@SFE_STREAMLIT_STAGE<br/>Dashboard files]
            end
            
            subgraph "ML Constructs"
                MLModel[SFE_GLOBAL_FORECAST_MODEL<br/>ML.FORECAST object]
                FeatureStore[SFE_FEATURE_STORE<br/>Feature views]
                Registry[Model Registry<br/>SFE_STREAM_FORECAST_MODEL]
            end
        end
        
        subgraph "Compute Services"
            MLFunctions[Snowflake ML Functions<br/>Serverless compute]
            SnowparkRuntime[Snowpark Runtime<br/>Python 3.10 + packages]
            Tasks[Task Scheduler<br/>Serverless compute]
            StreamlitApp[Streamlit in Snowflake<br/>SFE_MONITORING_DASHBOARD]
        end
        
        subgraph "Monitoring"
            AccountUsage[SNOWFLAKE.ACCOUNT_USAGE<br/>Cost & performance metrics]
        end
    end
    
    subgraph "External Services"
        Anaconda[Anaconda Repository<br/>repo.anaconda.com/pkgs/snowflake<br/>Python packages: xgboost, pandas]
    end
    
    Snowsight -->|HTTPS| CloudServices
    Python -->|HTTPS<br/>Port 443| CloudServices
    SnowSQL -->|HTTPS<br/>Port 443| CloudServices
    
    CloudServices -->|Execute| SFEWH
    CloudServices -->|Metadata| DB
    
    SFEWH -->|Read/Write| InputTable
    SFEWH -->|Read/Write| OutputML
    SFEWH -->|Read/Write| OutputSP
    SFEWH -->|Read| CostParams
    
    SFEWH -->|Store artifacts| ModelStage
    SFEWH -->|Read artifacts| ModelStage
    SFEWH -->|Host files| StreamlitStage
    
    MLFunctions -->|Train/Infer| MLModel
    MLFunctions -->|Write results| OutputML
    
    SnowparkRuntime -->|Execute procedures| SFEWH
    SnowparkRuntime -->|Feature engineering| FeatureStore
    SnowparkRuntime -->|Train model| Registry
    SnowparkRuntime -->|Load packages| Anaconda
    
    Tasks -->|Schedule| MLFunctions
    Tasks -->|Schedule| SnowparkRuntime
    
    StreamlitApp -->|Query| AccountUsage
    StreamlitApp -->|Execute on| SFEWH
    
    SFEWH -->|Log queries| AccountUsage
    Tasks -->|Log execution| AccountUsage
    
    style Snowsight fill:#e1f5ff
    style Python fill:#e1f5ff
    style SFEWH fill:#d4edda
    style MLFunctions fill:#fff3cd
    style AccountUsage fill:#f8d7da
```

## Component Descriptions

### Client Layer

#### Snowsight Web UI
- **Purpose:** Primary interface for SQL execution and visual data exploration
- **Technology:** Browser-based Snowflake UI
- **Protocol:** HTTPS over port 443
- **Authentication:** Username/password, MFA, or SSO
- **Access URL:** `https://<account>.snowflakecomputing.com`
- **Usage:** Execute SQL scripts, deploy Streamlit apps, view query profiles

#### Python Client (Snowpark SDK)
- **Purpose:** Programmatic access for feature store and model registry setup
- **Technology:** `snowflake-snowpark-python` library
- **Protocol:** HTTPS over port 443
- **Authentication:** Key-pair authentication (recommended) or username/password
- **Configuration:** `~/.snowflake/connections.toml` or environment variables
- **Usage:** Run `python/snowpark_setup.py` for feature store initialization

#### SnowSQL CLI
- **Purpose:** Command-line interface for SQL execution and file uploads
- **Technology:** Native Snowflake CLI tool
- **Protocol:** HTTPS over port 443
- **Authentication:** Same as Snowsight
- **Usage:** Optional for stage file uploads (`PUT` command)

### Snowflake Account Architecture

#### Cloud Services Layer
- **Purpose:** Query parsing, optimization, metadata management, authentication
- **Technology:** Snowflake-managed infrastructure (multi-tenant)
- **Network:** Internal Snowflake network (abstracted from users)
- **Cost:** Minimal (~10% of compute costs, usually within free tier)
- **Function:** Routes queries to warehouses, manages transactions, enforces security

#### Virtual Warehouse: SFE_SP_WH
- **Purpose:** Dedicated compute cluster for all forecasting workloads
- **Type:** Snowpark-Optimized (enhanced for Python execution)
- **Size:** MEDIUM (16 nodes, 128 GB memory)
- **Credit Rate:** 6 credits/hour for Snowpark-Optimized MEDIUM
- **Auto-Suspend:** 60 seconds (aggressive cost control)
- **Auto-Resume:** TRUE (seamless restart on query submission)
- **Concurrency:** Single cluster (suitable for demo/lab workload)
- **Network:** Internal Snowflake network (no external connectivity)
- **Best Practice:** Single warehouse for cost attribution simplicity

### Storage Layer

#### SNOWFLAKE_EXAMPLE Database
- **Purpose:** Isolated namespace for demo/lab objects
- **Location:** Cloud storage (S3/Azure/GCS depending on account region)
- **Format:** Columnar micro-partitions (Snowflake proprietary)
- **Encryption:** AES-256 (at rest and in transit)
- **Cost:** ~$40/TB/month for compressed storage

#### FORECASTING Schema
- **Purpose:** Logical container for all forecasting tables and objects
- **Isolation:** Separate from production schemas
- **Access Control:** Governed by role-based grants

#### Stages
- **SFE_MODEL_STAGE:** Stores serialized XGBoost model artifacts (`.pkl` files)
- **SFE_STREAMLIT_STAGE:** Stores Streamlit dashboard Python files
- **Type:** Internal stages (cloud storage in Snowflake account)
- **Access:** Via `@SNOWFLAKE_EXAMPLE.FORECASTING.SFE_MODEL_STAGE` reference

### Compute Services

#### Snowflake ML Functions (Serverless)
- **Purpose:** Native forecasting model training and inference
- **Technology:** Managed ML service (algorithm details proprietary)
- **Compute Model:** Serverless (automatic scaling, pay-per-use)
- **Network:** Internal Snowflake network
- **Cost:** Billed as warehouse compute time (not a separate service)
- **Function:** `SNOWFLAKE.ML.FORECAST` for model creation, `model!FORECAST()` for inference

#### Snowpark Runtime
- **Purpose:** Python execution environment for stored procedures
- **Technology:** Containerized Python 3.10 runtime with Anaconda integration
- **Packages:** Preloaded: `snowflake-snowpark-python`, `pandas`, `numpy`, `xgboost`, `joblib`
- **Memory:** Optimized for in-memory DataFrame operations
- **Network:** Outbound HTTPS to Anaconda repository (package loading only)
- **Execution:** Always runs on Snowpark-Optimized warehouse

#### Task Scheduler (Serverless)
- **Purpose:** Cron-based automation for model training and inference
- **Technology:** Snowflake-managed task engine
- **Scheduling:** Cron expressions (e.g., `0 2 * * 1` for weekly Sunday 2 AM)
- **Compute:** Uses specified warehouse (`SFE_SP_WH`) when task executes
- **Cost:** No separate task cost—only billed for warehouse time during execution
- **Examples:**
  - `SFE_TASK_TRAIN_GLOBAL`: Weekly model retraining
  - `SFE_TASK_FORECAST_GLOBAL`: Daily inference
  - `SFE_TASK_FORECAST_ML`: Daily ML Functions refresh

#### Streamlit in Snowflake
- **Purpose:** Interactive monitoring dashboard hosted natively in Snowflake
- **Technology:** Streamlit framework (Python-based)
- **Hosting:** Fully managed by Snowflake (no external servers)
- **Execution:** Runs on specified warehouse (`SFE_SP_WH`)
- **Access:** Via Snowsight UI or direct URL
- **Network:** HTTPS only (port 443)
- **Authentication:** Inherits Snowflake user authentication
- **Benefits:** No local Python environment, easy team sharing

### Monitoring

#### SNOWFLAKE.ACCOUNT_USAGE Schema
- **Purpose:** Historical query and cost telemetry
- **Technology:** System-provided views (read-only)
- **Latency:** 45 minutes to 3 hours (not real-time)
- **Retention:** 365 days
- **Key Views:**
  - `QUERY_HISTORY`: All executed queries with tags and performance metrics
  - `WAREHOUSE_METERING_HISTORY`: Credit consumption by warehouse
  - `TASK_HISTORY`: Scheduled task execution logs
- **Access:** Requires `ACCOUNTADMIN` role or explicit grant
- **Network:** Internal metadata store (no external access)

### External Services

#### Anaconda Repository
- **Purpose:** Python package distribution for Snowpark
- **URL:** `https://repo.anaconda.com/pkgs/snowflake`
- **Protocol:** HTTPS
- **Packages Used:** `xgboost`, `pandas`, `numpy`, `joblib`, `scikit-learn`
- **Network Flow:** Snowpark runtime → Anaconda repo (outbound HTTPS only)
- **Security:** TLS-encrypted, no inbound connections required
- **Note:** Packages cached within Snowflake after first load

## Network Security

### Firewall Requirements
- **Outbound HTTPS (Port 443):** Required for client → Snowflake communication
- **No Inbound Connections:** Snowflake is SaaS—no client-side listening ports
- **VPN/PrivateLink:** Optional (not required for this lab)

### Authentication Methods
1. **Username/Password + MFA:** Standard authentication
2. **Key-Pair Authentication:** Recommended for Python scripts (private key stored locally)
3. **SSO/SAML:** Enterprise authentication (not required for lab)
4. **OAuth:** Token-based authentication (advanced)

### Data Encryption
- **In-Transit:** TLS 1.2+ for all client-server communication
- **At-Rest:** AES-256 for all data in Snowflake storage
- **Key Management:** Snowflake-managed keys (customer-managed keys optional)

## Network Topology Summary

| Connection | Protocol | Port | Direction | Purpose |
|------------|----------|------|-----------|---------|
| Client → Snowflake | HTTPS | 443 | Outbound | All SQL queries and data transfers |
| Snowpark → Anaconda | HTTPS | 443 | Outbound | Python package downloads |
| Warehouse → Storage | Internal | N/A | Internal | Data reads/writes (Snowflake-internal) |
| Cloud Services → Warehouse | Internal | N/A | Internal | Query dispatch (Snowflake-internal) |

## Performance Optimization

### Warehouse Sizing
- **Current:** MEDIUM (sufficient for demo workload)
- **Training Workload:** Consider LARGE if training time exceeds 5 minutes
- **BI Dashboard:** SMALL or X-SMALL sufficient for Streamlit queries
- **Monitoring:** Track warehouse load via `WAREHOUSE_LOAD_HISTORY` view

### Network Optimization
- **Result Set Limit:** Use `LIMIT` clauses to reduce data transfer
- **Stage Files:** Store large model artifacts in stages (not in tables)
- **Batch Operations:** Use stored procedures for multi-step workflows to reduce round-trips

## Change History

See `.cursor/DIAGRAM_CHANGELOG.md` for version history.



