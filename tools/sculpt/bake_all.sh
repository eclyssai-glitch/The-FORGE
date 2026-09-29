#!/usr/bin/env bash
# Regenerates every sculpture (assets/meshes/*.obj + *.json) from tools/sculpt/*.py.
# Deterministic: same inputs -> same bytes. Needs the tools venv /opt/korium-py (ADR-013);
# the game itself never runs Python. Extra arguments go to bake_all.py (e.g. --only hand_left).
set -euo pipefail
cd "$(dirname "$0")/../.."
PY=/opt/korium-py/bin/python
if [ ! -x "$PY" ]; then
  echo "bake_all: $PY not found (tools venv with numpy, scipy, scikit-image)." >&2
  exit 127
fi
export OPENBLAS_NUM_THREADS=1 OMP_NUM_THREADS=1 MKL_NUM_THREADS=1
exec "$PY" tools/sculpt/bake_all.py "$@"
