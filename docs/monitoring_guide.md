# Cost and Performance Monitoring Guide

This guide provides comprehensive instructions for monitoring and optimizing your Snowflake forecasting workloads.

## Table of Contents

1. [Overview](#overview)
2. [Query Tagging Strategy](#query-tagging-strategy)
3. [Monitoring Queries](#monitoring-queries)
4. [Streamlit Dashboard](#streamlit-dashboard)
5. [Interpreting Metrics](#interpreting-metrics)
6. [Optimization Strategies](#optimization-strategies)
7. [Troubleshooting](#troubleshooting)

## Overview

Cost and performance monitoring is essential for:

- **Cost Attribution**: Understand which workloads (training, inference, data prep) consume the most resources
- **Performance Optimization**: Identify bottlenecks, queuing issues, and slow queries
- **Capacity Planning**: Determine appropriate warehouse sizing and scaling strategies
- **Budget Control**: Prevent cost overruns with resource monitors and alerts

### Monitoring Components

This project includes three monitoring approaches:

1. **Query Tags**: Embedded in SQL and Python code for automatic cost attribution
2. **SQL Monitoring Queries**: Manual queries for detailed analysis (`sql/06_monitoring_queries.sql`)
3. **Streamlit in Snowflake Dashboard**: Interactive visualizations running natively in Snowflake (`streamlit/monitoring/`)

## Query Tagging Strategy

### What are Query Tags?

Query tags are metadata labels attached to queries that enable cost attribution and workload analysis. They're captured in `ACCOUNT_USAGE.QUERY_HISTORY` for later analysis.

### Tagging Format

We use a structured format for consistency:

```
WORKLOAD:{type}|PATH:{approach}
```

**Workload Types:**
- `TRAINING`: Model training operations
- `INFERENCE`: Forecasting/prediction queries
- `DATA_PREP`: Data loading and preparation

**Model Paths:**
- `ML_FUNCTIONS`: Using `SNOWFLAKE.ML.FORECAST`
- `SNOWPARK_XGBOOST`: Using Snowpark stored procedures with XGBoost

### Examples

```sql
-- Training with ML Functions
ALTER SESSION SET QUERY_TAG = 'WORKLOAD:TRAINING|PATH:ML_FUNCTIONS';

-- Inference with Snowpark XGBoost
ALTER SESSION SET QUERY_TAG = 'WORKLOAD:INFERENCE|PATH:SNOWPARK_XGBOOST';

-- Data preparation (no path needed)
ALTER SESSION SET QUERY_TAG = 'WORKLOAD:DATA_PREP';

-- Always reset when done
ALTER SESSION UNSET QUERY_TAG;
```

### Implementation Notes

- Tags are automatically set in all SQL scripts and Python stored procedures
- Scheduled tasks include `SCHEDULED:TRUE` flag in their tags
- Tags persist for the session until explicitly unset

## Monitoring Queries

The `sql/06_monitoring_queries.sql` script provides comprehensive monitoring queries organized into sections:

### Section 1: Warehouse Performance

**1.1 Warehouse Utilization**
- Hourly credit consumption over 7 days
- Execution counts and averages
- Use for: Identifying peak usage periods

**1.2 Warehouse Load History**
- Detect query queuing issues
- Monitor concurrent query counts
- Use for: Determining if warehouse scaling is needed

**Query Interpretation:**
- `avg_running > warehouse_size`: Good utilization
- `avg_queued_load > 0`: Queries waiting for resources (consider scaling up)
- `avg_blocked > 0`: Resource contention (investigate query conflicts)

### Section 2: Cost Analysis by Query Tag

**2.1 Credit Consumption by Workload Type**
- Shows cost attribution across TRAINING, INFERENCE, DATA_PREP
- Includes query counts and execution hours
- Calculates estimated costs in dollars

**2.2 Cost Comparison: ML Functions vs Snowpark**
- Side-by-side comparison of both forecasting approaches
- Average costs per query
- Total costs by workload type

**Use Case:**
Determine which forecasting path is more cost-effective for your workload patterns.

### Section 3: Query Performance

**3.1 Longest-Running Queries**
- Identifies queries taking the most time
- Includes queuing time breakdown
- Shows data scanned and rows produced

**3.2 Most Expensive Queries**
- Ranked by credit consumption
- Helps prioritize optimization efforts

**3.3 Execution Patterns by Hour**
- Understand when workloads run
- Optimize scheduling to avoid conflicts

### Section 4: Warehouse Efficiency

**4.1 Idle Time Analysis**
- Calculates warehouse hours vs. active query hours
- Identifies wasted credits from idle time
- Suggests auto-suspend timeout optimization

**4.2 Auto-Suspend Effectiveness**
- Analyzes session duration patterns
- Helps tune auto-suspend timeout

### Section 5: Forecasting Workload Insights

**5.1 Model Training Frequency**
- Tracks training job patterns
- Average and max training duration
- Data scanned per training run

**5.2 Inference Workload Statistics**
- Daily inference run counts
- Performance consistency metrics
- Average rows forecasted

### Section 6: Resource Monitors (Optional)

Example implementation for automated cost controls:
- Progressive alerts (50%, 75%, 90%)
- Automatic suspension to prevent overages
- Credit quota management

### Section 7: Executive Summary

Single query providing high-level overview:
- Total credits and costs
- Query counts by workload
- Average query performance

## Streamlit in Snowflake Dashboard

The interactive dashboard (`streamlit/monitoring/SFE_MONITORING_DASHBOARD.py`) runs natively in Snowflake.

### Benefits

- **No Local Setup**: Runs entirely in Snowflake, no Python environment needed
- **Secure**: Uses your existing Snowflake authentication
- **Easy Sharing**: Share with team members through Snowflake roles
- **Integrated**: Direct access to ACCOUNT_USAGE views without connection management

### Deployment

**Step 1: Upload Dashboard File**

Using Snowsight (Web UI):
1. Navigate to: Data → Databases → SNOWFLAKE_EXAMPLE → FORECASTING → Stages
2. Click on `SFE_STREAMLIT_STAGE`
3. Click **+ Files** and upload `SFE_MONITORING_DASHBOARD.py`

Using SnowSQL:
```bash
PUT file://./streamlit/monitoring/SFE_MONITORING_DASHBOARD.py 
  @SNOWFLAKE_EXAMPLE.FORECASTING.SFE_STREAMLIT_STAGE 
  AUTO_COMPRESS=FALSE OVERWRITE=TRUE;
```

**Step 2: Create Streamlit App**

Run `streamlit/monitoring/deploy_streamlit.sql` or execute:
```sql
CREATE OR REPLACE STREAMLIT SNOWFLAKE_EXAMPLE.FORECASTING.SFE_MONITORING_DASHBOARD
    ROOT_LOCATION = '@SNOWFLAKE_EXAMPLE.FORECASTING.SFE_STREAMLIT_STAGE'
    MAIN_FILE = 'SFE_MONITORING_DASHBOARD.py'
    QUERY_WAREHOUSE = 'SFE_SP_WH';
```

**Step 3: Access Dashboard**

Via SQL:
```sql
SHOW STREAMLITS IN SCHEMA SNOWFLAKE_EXAMPLE.FORECASTING;
```

Via Snowsight:
- Navigate to **Projects** → **Streamlit**
- Click on `SFE_MONITORING_DASHBOARD`

### Dashboard Features

#### Tab 1: Warehouse Performance
- **Summary Metrics**: Total credits, costs, executions
- **Credit Usage Chart**: Hourly consumption trends
- **Load Analysis**: Running vs queued queries
- **Alerts**: Automatic queuing detection

#### Tab 2: Cost Analytics
- **Cost Distribution**: Pie chart by workload type
- **Path Comparison**: ML Functions vs Snowpark costs
- **Daily Trend**: Area chart showing spending over time
- **Projections**: Estimated monthly costs

#### Tab 3: Query Analysis
- **Slowest Queries**: Bar chart of top 10
- **Performance Summary**: Statistics by workload type
- **Execution Distribution**: Histogram of query times
- **Queue Analysis**: Queries experiencing delays

#### Tab 4: Recommendations
- **Automated Analysis**: AI-generated optimization suggestions
- **Priority Levels**: HIGH, MEDIUM, LOW
- **Action Items**: Specific SQL commands to implement fixes
- **Best Practices**: Summary of optimization strategies

### Dashboard Configuration

- **Time Window**: Select 7, 14, or 30 days
- **Auto-refresh**: Enable 5-minute refresh for real-time monitoring
- **Cost Parameters**: Displays configured credit costs

## Interpreting Metrics

### Key Performance Indicators (KPIs)

#### Cost Metrics

| Metric | Good Range | Action Needed |
|--------|-----------|---------------|
| Daily cost variance | < 20% | Investigate spikes > 30% |
| Untagged query % | < 5% | Tag all forecasting queries |
| Training cost/run | Baseline established | Optimize if trending up |
| Inference cost/run | Stable | Alert if 2x increase |

#### Performance Metrics

| Metric | Good Range | Action Needed |
|--------|-----------|---------------|
| Avg query time | Stable | Investigate 50%+ increases |
| Queued queries | 0 | Scale up if consistently > 0 |
| Warehouse utilization | 60-80% | Too low: consolidate; Too high: scale |
| Queue time | < 5% of execution | Immediate scaling needed if > 20% |

#### Efficiency Metrics

| Metric | Target | Optimization |
|--------|--------|--------------|
| Idle time % | < 15% | Reduce auto-suspend timeout |
| Credits per execution | Trending down | Good optimization |
| Data scanned/query | Stable | Use clustering/caching if increasing |

## Optimization Strategies

### Cost Optimization

#### 1. Warehouse Sizing
```sql
-- Start small, scale up based on actual performance
ALTER WAREHOUSE SFE_SP_WH SET WAREHOUSE_SIZE = 'SMALL';

-- Monitor queuing, scale up if needed
ALTER WAREHOUSE SFE_SP_WH SET WAREHOUSE_SIZE = 'MEDIUM';
```

#### 2. Auto-Suspend Optimization
```sql
-- Aggressive for batch workloads (minimize idle costs)
ALTER WAREHOUSE SFE_SP_WH SET AUTO_SUSPEND = 60;

-- Moderate for interactive workloads (balance responsiveness vs cost)
ALTER WAREHOUSE SFE_SP_WH SET AUTO_SUSPEND = 300;
```

#### 3. Resource Monitors
```sql
-- Prevent budget overruns
CREATE RESOURCE MONITOR FORECASTING_BUDGET WITH
    CREDIT_QUOTA = 100
    FREQUENCY = MONTHLY
    START_TIMESTAMP = IMMEDIATELY
    TRIGGERS
        ON 75 PERCENT DO NOTIFY
        ON 90 PERCENT DO SUSPEND
        ON 100 PERCENT DO SUSPEND_IMMEDIATE;

ALTER WAREHOUSE SFE_SP_WH SET RESOURCE_MONITOR = FORECASTING_BUDGET;
```

#### 4. Scheduled Workload Optimization
```sql
-- Run heavy training jobs during off-peak hours
CREATE OR REPLACE TASK SFE_TASK_TRAIN_GLOBAL
    WAREHOUSE = SFE_SP_WH
    SCHEDULE = 'USING CRON 0 2 * * 1 America/Los_Angeles'  -- Sundays at 2 AM
AS
    CALL SFE_TRAIN_GLOBAL_MODEL();
```

### Performance Optimization

#### 1. Query Optimization
- Review slowest queries in monitoring dashboard
- Check execution plans: `EXPLAIN <query>`
- Optimize joins and filters
- Use incremental processing where possible

#### 2. Warehouse Scaling
```sql
-- For high concurrency (multiple users/apps)
ALTER WAREHOUSE SFE_SP_WH SET
    MIN_CLUSTER_COUNT = 1
    MAX_CLUSTER_COUNT = 3
    SCALING_POLICY = 'STANDARD';

-- For batch processing with queuing
ALTER WAREHOUSE SFE_SP_WH SET WAREHOUSE_SIZE = 'LARGE';
```

#### 3. Data Optimization
```sql
-- Add clustering for frequently filtered columns
ALTER TABLE FORECAST_INPUT_GLOBAL CLUSTER BY (REGION, WEEK_ENDING);

-- Create materialized views for expensive aggregations
CREATE MATERIALIZED VIEW WEEKLY_STREAM_SUMMARY AS
SELECT
    REGION,
    WEEK_ENDING,
    SUM(STREAMS) AS total_streams,
    COUNT(DISTINCT ISRC) AS track_count
FROM FORECAST_INPUT_GLOBAL
GROUP BY REGION, WEEK_ENDING;
```

#### 4. Caching Strategy
- Use result caching for repeated queries (automatic in Snowflake)
- Consider persisting intermediate results for multi-stage processing

### Monitoring Best Practices

1. **Regular Reviews**: Weekly review of monitoring dashboard
2. **Baseline Metrics**: Establish baselines for normal performance
3. **Alert Thresholds**: Set up notifications for anomalies
4. **Documentation**: Document optimization changes and results
5. **Continuous Improvement**: Iterate on configurations based on actual usage

## Troubleshooting

### Common Issues and Solutions

#### Issue: High Queuing

**Symptoms:**
- `avg_queued_load > 0` in warehouse load history
- Queries showing queue time in performance analysis

**Solutions:**
1. Scale up warehouse: `ALTER WAREHOUSE SFE_SP_WH SET WAREHOUSE_SIZE = 'LARGE'`
2. Enable multi-cluster: `ALTER WAREHOUSE SFE_SP_WH SET MAX_CLUSTER_COUNT = 3`
3. Stagger scheduled tasks to reduce concurrency

#### Issue: High Idle Time

**Symptoms:**
- Warehouse idle percentage > 30%
- Many short sessions in warehouse metering history

**Solutions:**
1. Reduce auto-suspend: `ALTER WAREHOUSE SFE_SP_WH SET AUTO_SUSPEND = 30`
2. Consolidate workloads to fewer warehouses
3. Use separate warehouses for batch vs interactive workloads

#### Issue: Inconsistent Query Performance

**Symptoms:**
- High variance in execution times for similar queries
- Some queries much slower than others

**Solutions:**
1. Check for data skew in joins
2. Verify warehouse is not suspending between queries
3. Review query execution plans for inefficiencies
4. Consider result caching for repeated queries

#### Issue: Cost Overruns

**Symptoms:**
- Monthly costs exceeding budget
- Unexpected spikes in credit consumption

**Solutions:**
1. Implement resource monitors with suspension triggers
2. Review most expensive queries and optimize
3. Audit untagged queries (may be unauthorized usage)
4. Verify scheduled tasks are not running too frequently

#### Issue: Dashboard Connection Errors

**Symptoms:**
- Streamlit dashboard fails to connect
- "Error fetching data" messages

**Solutions:**
1. Verify credentials in environment variables or connections.toml
2. Test connection: `python -c "from config import test_connection; print(test_connection())"`
3. Check network connectivity to Snowflake
4. Verify user has appropriate permissions (USAGE on warehouse, SELECT on ACCOUNT_USAGE)

#### Issue: Missing Data in Monitoring Queries

**Symptoms:**
- Empty results from ACCOUNT_USAGE queries
- Recent data not appearing

**Solutions:**
1. Wait for ACCOUNT_USAGE latency (up to 45 minutes for QUERY_HISTORY)
2. Check if queries were successful (execution_status = 'SUCCESS')
3. Verify warehouse name matches exactly ('SFE_SP_WH')
4. Ensure user has ACCOUNT_USAGE access (grant by ACCOUNTADMIN)

### Getting Help

If you continue to experience issues:

1. **Check Snowflake Documentation**: https://docs.snowflake.com/
2. **Review Query History**: Use Snowflake web UI to examine recent queries
3. **Check Warehouse Activity**: Monitor warehouse utilization in Snowflake UI
4. **Consult Support**: Contact Snowflake support for account-specific issues

## Appendix: Permissions Requirements

### Monitoring Queries
- `USAGE` on warehouse SFE_SP_WH
- `SELECT` on `SNOWFLAKE.ACCOUNT_USAGE.*` views (requires ACCOUNTADMIN grant)
- `SELECT` on `SNOWFLAKE_EXAMPLE.FORECASTING.*` tables

### Resource Monitors
- `ACCOUNTADMIN` role or delegated monitor privileges

### Grant Examples
```sql
-- Grant monitoring access to a role
GRANT USAGE ON WAREHOUSE SFE_SP_WH TO ROLE DATA_ANALYST;
GRANT MONITOR ON WAREHOUSE SFE_SP_WH TO ROLE DATA_ANALYST;
GRANT IMPORTED PRIVILEGES ON DATABASE SNOWFLAKE TO ROLE DATA_ANALYST;

-- Grant resource monitor management
GRANT CREATE RESOURCE MONITOR ON ACCOUNT TO ROLE WAREHOUSE_ADMIN;
```

## Conclusion

Effective cost and performance monitoring enables:
- Predictable forecasting costs
- Optimal warehouse performance
- Data-driven optimization decisions
- Proactive issue detection

Use this guide as a reference for implementing and maintaining monitoring for your Snowflake forecasting workloads.

