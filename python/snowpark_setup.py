"""
This script sets up the Snowflake Feature Store and Model Registry for the Snowpark lab path.

It performs the following actions:
1. Connects to Snowflake using your established credentials.
2. Creates the Feature Store if it doesn't exist.
3. Registers a 'TRACK' entity.
4. Creates and registers a 'STREAM_FEATURES' feature view.
5. (Optional) Creates a scheduled task to refresh the feature view.
6. (Optional) Registers a placeholder model in the Model Registry.
"""
# This script relies on an established Snowflake connection.
# Please ensure your credentials are set up via a ~/.snowflake/connections.toml file
# or through environment variables.
# See: https://docs.snowflake.com/en/developer-guide/snowpark/python/creating-session

import importlib.metadata
from packaging import version
from snowflake.ml.feature_store import FeatureStore, CreationMode, Entity, FeatureView
from snowflake.ml.registry import Registry
from snowflake.ml._internal.exceptions import exceptions as snowml_exceptions
from snowflake.snowpark import Session, Window
from snowflake.snowpark import functions as F
import joblib

# Simple placeholder model for registry demonstration
from sklearn.linear_model import LinearRegression
import numpy as np


# Version check for Snowpark
MIN_SNOWPARK_VERSION = "1.9.0"
try:
    snowpark_version = importlib.metadata.version("snowflake-snowpark-python")
    if version.parse(snowpark_version) < version.parse(MIN_SNOWPARK_VERSION):
        raise ImportError(
            f"Snowpark version {snowpark_version} is installed. "
            f"This script requires version {MIN_SNOWPARK_VERSION} or higher. "
            "Please upgrade with: pip install --upgrade -r requirements.txt"
        )
except importlib.metadata.PackageNotFoundError:
    pass # Let the import errors below handle this case


# Handle API naming differences between Snowpark versions
UNBOUNDED_PRECEDING = getattr(Window, "unbounded_preceding", getattr(Window, "unboundedPreceding"))
CURRENT_ROW = getattr(Window, "current_row", getattr(Window, "currentRow"))


DATABASE_NAME = "SNOWFLAKE_EXAMPLE"
SCHEMA_NAME = "FORECASTING"
WAREHOUSE_NAME = "SFE_SP_WH"


def setup_feature_store(session: Session):
    """Creates the Feature Store and registers the entity and feature view."""
    print("Setting up Feature Store...")
    fs = FeatureStore(
        session=session,
        database=DATABASE_NAME,
        name='SFE_FEATURE_STORE',
        default_warehouse='SFE_SP_WH',
        creation_mode=CreationMode.CREATE_IF_NOT_EXIST,
    )

    track_entity = Entity(name='SFE_TRACK', join_keys=['ISRC'])
    fs.register_entity(track_entity)
    print("  - 'SFE_TRACK' entity registered.")

    # Remove any existing feature view so reruns after schema changes succeed (see docs: https://docs.snowflake.com/en/developer-guide/snowflake-ml/feature-store/manage#delete-feature-view)
    try:
        fs.delete_feature_view('SFE_STREAM_FEATURES', version='v1')
        print("  - Existing 'SFE_STREAM_FEATURES' feature view (v1) deleted.")
    except (snowml_exceptions.SnowflakeMLException, TypeError, ValueError) as e:
        # Feature view doesn't exist or API incompatibility - safe to proceed
        if "Failed to find FeatureView" not in str(e):
            print(f"  - Note: Could not delete existing feature view: {e}")
        else:
            print("  - 'SFE_STREAM_FEATURES' feature view does not exist, proceeding.")

    # Build the feature DataFrame using the Snowpark DataFrame API
    source_df = session.table("SNOWFLAKE_EXAMPLE.FORECASTING.FORECAST_INPUT_GLOBAL").filter(F.col("REGION") == "Global")

    # Define window specifications for aggregations
    w_avg = Window.partition_by("ISRC").order_by("WEEK_ENDING").rows_between(UNBOUNDED_PRECEDING, CURRENT_ROW)
    w_sum = Window.partition_by("ISRC").order_by("WEEK_ENDING").rows_between(-3, CURRENT_ROW)

    # Create the feature columns
    feature_df = source_df.select(
        "ISRC",
        "WEEK_ENDING",
        F.avg("STREAMS").over(w_avg).alias("AVG_STREAMS_TO_DATE"),
        F.sum("STREAMS").over(w_sum).alias("STREAMS_LAST_4_WEEKS")
    )

    stream_features = FeatureView(
        name='SFE_STREAM_FEATURES',
        entities=[track_entity],
        feature_df=feature_df,
        timestamp_col="WEEK_ENDING"
    )
    fs.register_feature_view(stream_features, version="v1")
    print("  - 'SFE_STREAM_FEATURES' feature view registered.")
    print("Feature Store setup complete.")


def setup_model_registry(session: Session):
    """Registers a sample model in the Model Registry."""
    print("\nSetting up Model Registry...")
    registry = Registry(session=session, database_name=DATABASE_NAME, schema_name=SCHEMA_NAME)

    # Delete existing model if it exists to allow reruns
    # Use SQL DROP as it's more straightforward for this use case
    try:
        session.sql(f"DROP MODEL IF EXISTS {DATABASE_NAME}.{SCHEMA_NAME}.SFE_STREAM_FORECAST_MODEL").collect()
        print("  - Existing 'SFE_STREAM_FORECAST_MODEL' deleted (if it existed).")
    except Exception as e:
        print(f"  - Note: Could not delete existing model: {e}")

    # Create a dummy model for registration purposes
    model = LinearRegression()
    X = np.array([[1], [2], [3]])
    y = np.array([1, 2, 3])
    model.fit(X, y)

    # Log the model with sample input data to define its signature
    registry.log_model(
        model_name='SFE_STREAM_FORECAST_MODEL',
        version_name='v1',
        model=model,
        sample_input_data=X,
        comment='Placeholder model for registry demonstration'
    )
    print("  - 'SFE_STREAM_FORECAST_MODEL' (v1) registered.")
    print("Model Registry setup complete.")


def create_refresh_task(session: Session):
    """Creates a task to refresh the feature view."""
    print("\nCreating feature view refresh task (optional)...")
    task_sql = """
    /*
    -- Task to refresh feature views.
    -- This calls the training procedure as a placeholder for a dedicated refresh procedure.
    CREATE OR REPLACE TASK SNOWFLAKE_EXAMPLE.FORECASTING.SFE_TASK_REFRESH_FEATURES
      WAREHOUSE = SFE_SP_WH
      SCHEDULE = 'USING CRON 0 1 * * * America/Los_Angeles'
    AS
      CALL SNOWFLAKE_EXAMPLE.FORECASTING.SFE_TRAIN_GLOBAL_MODEL();

    ALTER TASK SNOWFLAKE_EXAMPLE.FORECASTING.SFE_TASK_REFRESH_FEATURES RESUME;
    */
    """
    print("  - The task creation SQL is commented out by default.")
    print("  - To enable, uncomment the block in this script and re-run.")
    # In a real scenario, you might run this conditionally.
    # For the lab, we leave it commented to keep it optional.
    # session.sql(task_sql).collect()
    print("Task creation step skipped (by default).")


if __name__ == "__main__":
    with Session.builder.create() as session:
        session.use_database(DATABASE_NAME)
        session.use_schema(SCHEMA_NAME)
        session.use_warehouse(WAREHOUSE_NAME)

        setup_feature_store(session)
        setup_model_registry(session)
        create_refresh_task(session)

        print("\nLab setup for Snowpark Path is complete.")
        print(f"Using warehouse: {session.get_current_warehouse()}")
        print(f"Using database: {session.get_current_database()}")
        print(f"Using schema: {session.get_current_schema()}")
