#!/usr/bin/env bash
set -euo pipefail

if ! command -v conda &>/dev/null; then
  echo "Conda is required for this script. Please install Miniconda or Anaconda first." >&2
  exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# Ensure conda shell integration is available
CONDA_BASE="$(conda info --base)"
# shellcheck source=/dev/null
source "$CONDA_BASE/etc/profile.d/conda.sh"

# Create a Conda environment using the Snowflake channel
conda create -n snowpark_env --override-channels \
  -c https://repo.anaconda.com/pkgs/snowflake \
  python=3.12 numpy pandas pyarrow -y
conda activate snowpark_env

# Apple Silicon workaround from the docs
conda config --env --set subdir osx-64

# Install Snowflake packages
pip install snowflake-snowpark-python snowflake-ml-python

# Install remaining Python dependencies (note: requirements.txt stored in repo root)
pip install -r "$REPO_ROOT/python/requirements.txt"

echo "Conda environment 'snowpark_env' is ready. Run: conda activate snowpark_env"
