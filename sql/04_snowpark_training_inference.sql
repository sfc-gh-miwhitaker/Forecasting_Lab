-- Snowpark stored procedures and tasks for Example forecasting (warehouse path)
-- Requires Snowpark Python, pandas API on Snowflake, and xgboost packages available.

-- Ensure packages exist before deployment:
-- SHOW PACKAGES LIKE 'xgboost'; -- Verify availability in Anaconda channel

-- Training stored procedure
CREATE OR REPLACE PROCEDURE SNOWFLAKE_EXAMPLE.FORECASTING.SFE_TRAIN_GLOBAL_MODEL()
RETURNS VARCHAR
LANGUAGE PYTHON
RUNTIME_VERSION = '3.10'
PACKAGES = ('snowflake-snowpark-python','pandas','numpy','xgboost','joblib')
HANDLER = 'main'
AS $$
from snowflake.snowpark import Session
from snowflake.snowpark import functions as F
import pandas as pd
import numpy as np
import joblib
from xgboost import XGBRegressor

MODEL_STAGE = '@SNOWFLAKE_EXAMPLE.FORECASTING.SFE_MODEL_STAGE'
MODEL_FILE = 'SFE_MODEL_GLOBAL_XGB_FULL.pkl'

FEATURE_COLUMNS = [
    'WEEK_SINCE_RELEASE','WEEK_SINCE_RELEASE_SQ','WEEK_SINCE_RELEASE_CB',
    'WEEK_OF_YEAR','IS_FIRST_4_WEEKS','LAST_WEEK_STREAMS','AVG_STREAMS_TO_DATE','PCT_CHANGE'
]
TARGET_COLUMN = 'LOG_STREAMS'

def build_features(df):
    df = df.select('ISRC','WEEK_ENDING','RELEASE_DATE','STREAMS') \
        .with_column('WEEK_SINCE_RELEASE', F.floor((F.datediff('day', F.col('RELEASE_DATE'), F.col('WEEK_ENDING')) / 7))) \
        .filter(F.col('WEEK_SINCE_RELEASE') < 52)

    w = F.window.partition_by('ISRC').order_by('WEEK_SINCE_RELEASE')
    df = df.with_column('LAST_WEEK_STREAMS', F.lag('STREAMS', 1).over(w)) \
        .with_column('AVG_STREAMS_TO_DATE', F.avg('STREAMS').over(w.rows_between(F.unbounded_preceding(), 0))) \
        .with_column('PCT_CHANGE', (F.col('STREAMS') - F.lag('STREAMS', 1).over(w)) / F.nullif(F.lag('STREAMS', 1).over(w), 0)) \
        .na.fill({'LAST_WEEK_STREAMS': 0, 'PCT_CHANGE': 0}) \
        .with_column('WEEK_SINCE_RELEASE_SQ', F.col('WEEK_SINCE_RELEASE') ** 2) \
        .with_column('WEEK_SINCE_RELEASE_CB', F.col('WEEK_SINCE_RELEASE') ** 3) \
        .with_column('WEEK_OF_YEAR', F.weekofyear('WEEK_ENDING')) \
        .with_column('IS_FIRST_4_WEEKS', F.iff(F.col('WEEK_SINCE_RELEASE') <= 3, F.lit(1), F.lit(0))) \
        .with_column('LOG_STREAMS', F.log1p('STREAMS'))
    return df

def main(session: Session) -> str:
    # Set query tag for cost attribution
    session.sql("ALTER SESSION SET QUERY_TAG = 'WORKLOAD:TRAINING|PATH:SNOWPARK_XGBOOST'").collect()
    
    base_df = session.table('SNOWFLAKE_EXAMPLE.FORECASTING.FORECAST_INPUT_GLOBAL').filter(F.col('REGION') == 'Global')
    qualifying = base_df.group_by('ISRC').agg(F.count_distinct('WEEK_ENDING').alias('WEEK_COUNT')) \
        .filter(F.col('WEEK_COUNT') > 10).select('ISRC')
    df = base_df.join(qualifying, 'ISRC')
    features_df = build_features(df)

    pdf = features_df.select(*FEATURE_COLUMNS, TARGET_COLUMN).to_pandas()
    if pdf.empty:
        return 'NO_DATA'

    X = pdf[FEATURE_COLUMNS]
    y = pdf[TARGET_COLUMN]

    model = XGBRegressor(
        n_estimators=300,
        max_depth=7,
        learning_rate=0.03,
        subsample=0.8,
        colsample_bytree=0.8,
        objective='reg:squarederror',
        tree_method='hist',
        random_state=42
    )
    model.fit(X, y)

    local_path = f'/tmp/{MODEL_FILE}'
    joblib.dump(model, local_path)
    session.file.put(local_path, f"{MODEL_STAGE}/{MODEL_FILE}", auto_compress=False, overwrite=True)

    registry = None
    try:
        from snowflake.ml.registry import Registry
        registry = Registry(session=session, database_name='SNOWFLAKE_EXAMPLE', schema_name='FORECASTING')
        registry.log_model(
            model_name='SFE_STREAM_FORECAST_MODEL',
            version_name='v1',
            model=model,
            comment='Global forecast model (XGBoost)'
        )
    except ImportError:
        pass
    
    # Reset query tag
    session.sql("ALTER SESSION UNSET QUERY_TAG").collect()
    
    return 'MODEL_SAVED'
$$;

-- Forecasting stored procedure
CREATE OR REPLACE PROCEDURE SNOWFLAKE_EXAMPLE.FORECASTING.SFE_FORECAST_GLOBAL(REGION STRING)
RETURNS STRING
LANGUAGE PYTHON
RUNTIME_VERSION = '3.10'
PACKAGES = ('snowflake-snowpark-python','pandas','numpy','xgboost','joblib')
HANDLER = 'main'
AS $$
from snowflake.snowpark import Session
from snowflake.snowpark import functions as F
import pandas as pd
import joblib
import numpy as np

MODEL_STAGE = '@SNOWFLAKE_EXAMPLE.FORECASTING.SFE_MODEL_STAGE'
MODEL_FILE = 'SFE_MODEL_GLOBAL_XGB_FULL.pkl'
INPUT_TABLE = 'SNOWFLAKE_EXAMPLE.FORECASTING.FORECAST_INPUT_GLOBAL'
OUTPUT_TABLE = 'SNOWFLAKE_EXAMPLE.FORECASTING.FORECAST_OUTPUT_GLOBAL'

FEATURE_COLUMNS = [
    'WEEK_SINCE_RELEASE','WEEK_SINCE_RELEASE_SQ','WEEK_SINCE_RELEASE_CB',
    'WEEK_OF_YEAR','IS_FIRST_4_WEEKS','LOG_LAST_WEEK_STREAMS','LOG_AVG_STREAMS_TO_DATE','LAST_WEEK_PCT_CHANGE'
]

def build_features(df):
    df = df.select('REGION','ISRC','DISPLAY_ARTIST','TRACK','RELEASE_DATE','WEEK_ENDING','STREAMS') \
        .with_column('WEEK_SINCE_RELEASE', F.floor((F.datediff('day', F.col('RELEASE_DATE'), F.col('WEEK_ENDING')) / 7)))

    w = F.window.partition_by('ISRC').order_by('WEEK_ENDING')
    df = df.with_column('LAST_WEEK_STREAMS', F.lag('STREAMS', 1).over(w)) \
        .with_column('AVG_STREAMS_TO_DATE', F.avg('STREAMS').over(w.rows_between(F.unbounded_preceding(), 0))) \
        .with_column('LAST_WEEK_PCT_CHANGE', (F.col('STREAMS') - F.lag('STREAMS', 1).over(w)) / F.nullif(F.lag('STREAMS', 1).over(w), 0)) \
        .na.fill({'LAST_WEEK_STREAMS': 0, 'LAST_WEEK_PCT_CHANGE': 0}) \
        .with_column('LOG_LAST_WEEK_STREAMS', F.log1p('LAST_WEEK_STREAMS')) \
        .with_column('LOG_AVG_STREAMS_TO_DATE', F.log1p('AVG_STREAMS_TO_DATE')) \
        .with_column('WEEK_SINCE_RELEASE_SQ', F.col('WEEK_SINCE_RELEASE') ** 2) \
        .with_column('WEEK_SINCE_RELEASE_CB', F.col('WEEK_SINCE_RELEASE') ** 3) \
        .with_column('WEEK_OF_YEAR', F.weekofyear('WEEK_ENDING')) \
        .with_column('IS_FIRST_4_WEEKS', F.iff(F.col('WEEK_SINCE_RELEASE') <= 3, F.lit(1), F.lit(0)))
    return df

def main(session: Session, REGION: str) -> str:
    # Set query tag for cost attribution
    session.sql("ALTER SESSION SET QUERY_TAG = 'WORKLOAD:INFERENCE|PATH:SNOWPARK_XGBOOST'").collect()
    session.sql('USE WAREHOUSE SFE_SP_WH').collect()
    session.file.get(f"{MODEL_STAGE}/{MODEL_FILE}", '/tmp', overwrite=True)
    model = joblib.load(f"/tmp/{MODEL_FILE}")

    base = session.table(INPUT_TABLE).filter(F.col('REGION') == REGION)
    features_df = build_features(base)

    pdf = features_df.select(*FEATURE_COLUMNS, 'REGION','ISRC','DISPLAY_ARTIST','TRACK','RELEASE_DATE','WEEK_ENDING','STREAMS').to_pandas()
    if pdf.empty:
        return 'NO_ROWS'

    preds = model.predict(pdf[FEATURE_COLUMNS])

    pdf['STREAMS_PREDICTED'] = np.expm1(preds)
    pdf['STREAMS_ACTUAL'] = pdf['STREAMS']
    pdf['IS_FORECAST'] = 1
    pdf['MODEL_FILE'] = MODEL_FILE
    pdf['RELEASE_DATE'] = pd.to_datetime(pdf['RELEASE_DATE']).dt.date
    pdf['WEEK_ENDING'] = pd.to_datetime(pdf['WEEK_ENDING']).dt.date

    observed = pdf.copy()
    observed['STREAMS_PREDICTED'] = None
    observed['IS_FORECAST'] = 0

    final_df = pd.concat([observed, pdf], ignore_index=True)
    final_df = final_df[['REGION','ISRC','DISPLAY_ARTIST','TRACK','RELEASE_DATE','WEEK_ENDING','STREAMS_ACTUAL','STREAMS_PREDICTED','IS_FORECAST','MODEL_FILE']]

    tmp_table = OUTPUT_TABLE + '_TMP'
    session.create_dataframe(final_df).write.save_as_table(tmp_table, mode='overwrite')
    session.sql(f"CREATE OR REPLACE TABLE {OUTPUT_TABLE} LIKE {tmp_table} COPY GRANTS").collect()
    session.sql(f"TRUNCATE TABLE {OUTPUT_TABLE}").collect()
    session.sql(f"INSERT INTO {OUTPUT_TABLE} SELECT * FROM {tmp_table}").collect()
    
    # Reset query tag
    session.sql("ALTER SESSION UNSET QUERY_TAG").collect()
    
    return 'OK'
$$;

-- Optional: To schedule training and forecasting, uncomment the following section.
-- Note: Query tags are set within the stored procedures themselves

-- Scheduling tasks
CREATE OR REPLACE TASK SNOWFLAKE_EXAMPLE.FORECASTING.SFE_TASK_TRAIN_GLOBAL
  WAREHOUSE = SFE_SP_WH
  SCHEDULE = 'USING CRON 0 2 * * 1 America/Los_Angeles'
  COMMENT = 'Weekly model training (Sundays at 2 AM PT)'
AS
  CALL SNOWFLAKE_EXAMPLE.FORECASTING.SFE_TRAIN_GLOBAL_MODEL();

CREATE OR REPLACE TASK SNOWFLAKE_EXAMPLE.FORECASTING.SFE_TASK_FORECAST_GLOBAL
  WAREHOUSE = SFE_SP_WH
  SCHEDULE = 'USING CRON 0 3 * * * America/Los_Angeles'
  COMMENT = 'Daily forecasting inference (3 AM PT)'
AS
  CALL SNOWFLAKE_EXAMPLE.FORECASTING.SFE_FORECAST_GLOBAL('Global');

ALTER TASK SNOWFLAKE_EXAMPLE.FORECASTING.SFE_TASK_TRAIN_GLOBAL RESUME;
ALTER TASK SNOWFLAKE_EXAMPLE.FORECASTING.SFE_TASK_FORECAST_GLOBAL RESUME;
