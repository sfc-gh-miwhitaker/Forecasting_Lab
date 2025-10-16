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

### Cost Analysis and Cleanup

6.  **`sql/05_cost_analysis.sql`**: (Optional) Demonstrates cost estimation examples using the cost estimator function. Does not require special ORGANIZATION_USAGE or ACCOUNT_USAGE privileges.

7.  **`sql/99_cleanup.sql`**: **Important!** Run this script to drop the `SNOWFLAKE_EXAMPLE` database and the `SFE_SP_WH` warehouse, removing all objects created during the lab.

## Repository Layout

-   `sql/`: Contains all the SQL scripts for the lab, organized by execution order.
-   `python/`: Contains helper Python code for the Snowpark path, including the Conda setup requirements.
-   `docs/`: Additional documentation, including architecture.
-   `data_quality/`: Placeholder for data quality checks.
