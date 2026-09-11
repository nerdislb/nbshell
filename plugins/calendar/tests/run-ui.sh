#!/usr/bin/env bash
set -euo pipefail
export PYTHONDONTWRITEBYTECODE=1
python3 "$(dirname "$0")/run-ui.py"
