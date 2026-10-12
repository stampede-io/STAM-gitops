#!/usr/bin/env bash
# STAM-402: unit-tests alerts.yaml's rules against promtool.
# Usage: bash observability/test-alerts.sh   (run from the repo root)
set -euo pipefail
cd "$(dirname "$0")"

PY=python3; python3 --version >/dev/null 2>&1 || PY=python
"$PY" extract-rules.py alerts.yaml .rules-generated.yaml
trap 'rm -f .rules-generated.yaml' EXIT

if command -v promtool >/dev/null 2>&1; then
  promtool test rules alerts_test.yaml
else
  # promtool isn't a standalone download; it ships inside the prometheus
  # image. No local Prometheus/promtool install needed either way.
  MSYS_NO_PATHCONV=1 docker run --rm -v "$(pwd):/work" -w /work \
    --entrypoint promtool prom/prometheus:v3.0.1 \
    test rules alerts_test.yaml
fi
