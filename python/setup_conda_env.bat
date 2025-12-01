@echo off
setlocal enabledelayedexpansion

REM Check if conda is installed
where conda >nul 2>nul
if %errorlevel% neq 0 (
    echo Conda is required for this script. Please install Miniconda or Anaconda first. >&2
    exit /b 1
)

REM Get the directory where this script is located
set "SCRIPT_DIR=%~dp0"
set "REPO_ROOT=%SCRIPT_DIR%.."

echo Creating Conda environment 'snowpark_env' using Snowflake channel...

REM Create a Conda environment using the Snowflake channel
call conda create -n snowpark_env --override-channels ^
  -c https://repo.anaconda.com/pkgs/snowflake ^
  python=3.12 numpy pandas pyarrow -y

if %errorlevel% neq 0 (
    echo Failed to create Conda environment. >&2
    exit /b 1
)

echo Activating snowpark_env environment...
call conda activate snowpark_env

if %errorlevel% neq 0 (
    echo Failed to activate Conda environment. >&2
    echo Try running: conda activate snowpark_env manually. >&2
    exit /b 1
)

echo Installing Snowflake packages...
call pip install snowflake-snowpark-python snowflake-ml-python

if %errorlevel% neq 0 (
    echo Failed to install Snowflake packages. >&2
    exit /b 1
)

echo Installing remaining Python dependencies...
call pip install -r "%REPO_ROOT%\python\requirements.txt"

if %errorlevel% neq 0 (
    echo Failed to install requirements.txt dependencies. >&2
    exit /b 1
)

echo.
echo ========================================
echo Conda environment 'snowpark_env' is ready!
echo.
echo To activate the environment, run:
echo     conda activate snowpark_env
echo.
echo Then you can run the setup script:
echo     python python\snowpark_setup.py
echo ========================================

endlocal



