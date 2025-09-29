#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

declare -a URLS=(
  "http://localhost:80"        # Nginx → FastAPI
  "http://localhost:8000/health"  # FastAPI direct (if exposed)
  "http://localhost:8080"      # Spark Master UI (internal 8080)
  "http://localhost:9090/json" # Spark Master REST JSON (if mapped)
  "http://localhost:8081"      # pgweb source (if used)
  "http://localhost:8082"      # pgweb dest (if used)
  "http://localhost:8099/health" # Airflow web health (if mapped)
  "http://localhost:5050"      # pgAdmin (if mapped)
  # add Redpanda, MinIO, etc. as appropriate:
  "http://localhost:9644/v1/status/ready"
  "http://localhost:9001/minio/health/live"
)

for u in "${URLS[@]}"; do
  "$ROOT/scripts/wait_on_http.sh" "$u" 90 || exit 1
done

# Spark specific
"$ROOT/scripts/spark_smoke.sh"
echo "All smokes passed ✅"
