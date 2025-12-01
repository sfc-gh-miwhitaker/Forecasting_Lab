# Cost Comparison & Estimation

## Inputs Needed

- Credits/hour for the Snowpark-optimized warehouse.
- Account-specific cost per credit (USD).
- Expected runtime in hours for each workload.

Populate `SNOWFLAKE_EXAMPLE.FORECASTING.SFE_COST_PARAMS` with these values; the helper function references the table.

## How to Retrieve Input Values

### Warehouse Credits per Hour

```sql
-- Estimate average compute credits/hour for the past 7 days
WITH recent_usage AS (
  SELECT START_TIME, END_TIME, CREDITS_USED_COMPUTE
  FROM ORGANIZATION_USAGE.WAREHOUSE_METERING_HISTORY
  WHERE WAREHOUSE_NAME = 'SFE_SP_WH'
    AND START_TIME >= DATEADD(day, -7, CURRENT_TIMESTAMP())
)
SELECT
  ROUND(SUM(CREDITS_USED_COMPUTE) / NULLIF(SUM(DATEDIFF('minute', START_TIME, END_TIME)) / 60, 0), 3) AS credits_per_hour
FROM recent_usage;
```

See documentation: [Warehouse Metering History](https://docs.snowflake.com/en/sql-reference/account-usage/warehouse_metering_history).

### Dollars per Credit

If your account has custom pricing, obtain the exact $/credit from Snowflake billing or your contract. For a quick sanity check based on historical invoices:

```sql
SELECT
  STATEMENT_DATE,
  CREDITS_USED,
  AMOUNT_DUE,
  ROUND(AMOUNT_DUE / NULLIF(CREDITS_USED, 0), 4) AS dollars_per_credit
FROM ORGANIZATION_USAGE.CREDIT_USAGE_DAILY
WHERE STATEMENT_DATE >= DATEADD(month, -3, CURRENT_DATE())
ORDER BY STATEMENT_DATE DESC;
```

Docs: [Credit Usage Views](https://docs.snowflake.com/en/sql-reference/account-usage/credit_usage#credit-usage-views).

### Expected Runtime

Use `QUERY_HISTORY` and `TASK_HISTORY` to inspect previous runs:

```sql
SELECT
  AVG(DATEDIFF('minute', START_TIME, END_TIME)) AS avg_minutes
FROM TABLE(INFORMATION_SCHEMA.QUERY_HISTORY())
WHERE QUERY_TEXT ILIKE '%SFE_TRAIN_GLOBAL_MODEL%'
  AND START_TIME >= DATEADD(day, -7, CURRENT_TIMESTAMP());
```

Docs: [QUERY_HISTORY table function](https://docs.snowflake.com/en/sql-reference/functions/query_history).

## Preflight Estimates

```sql
SELECT SNOWFLAKE_EXAMPLE.FORECASTING.SFE_ESTIMATE_WH_COST(
    RUNTIME_HOURS => 2,
    CREDITS_PER_HOUR => (
        SELECT PARAM_VALUE
        FROM SNOWFLAKE_EXAMPLE.FORECASTING.SFE_COST_PARAMS
        WHERE PARAM_NAME = 'SP_WH_LARGE_CREDITS_PER_HOUR'
    ),
    DOLLARS_PER_CREDIT => (
        SELECT PARAM_VALUE
        FROM SNOWFLAKE_EXAMPLE.FORECASTING.SFE_COST_PARAMS
        WHERE PARAM_NAME = 'DOLLARS_PER_CREDIT'
    )
);
```

## Post-Run Validation

- Warehouses: query `ORGANIZATION_USAGE.WAREHOUSE_METERING_HISTORY` for `SFE_SP_WH` over the execution window.

## Interpretation

- The Snowpark warehouse path suits recurring scheduled jobs with minimal operational overhead; Snowpark-optimized warehouses consume more credits/hour than standard warehouses, so verify the rate against your contract.
- The native `SNOWFLAKE.ML.FORECAST` path shares the same warehouse, so its cost is also driven by runtime and warehouse size.
