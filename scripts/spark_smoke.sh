#!/usr/bin/env bash
set -euo pipefail

MASTER_JSON="${SPARK_MASTER_JSON:-http://localhost:9090/json}"  # align with your port mapping
SPARK_SUBMIT="${SPARK_SUBMIT:-/opt/bitnami/spark/bin/spark-submit}"

# Wait for Master REST JSON
"$(dirname "$0")/wait_on_http.sh" "$MASTER_JSON" 120

echo "Spark version via REST:"
curl -fsS "$MASTER_JSON" | jq -r '.sparkVersion'

echo "Spark version via spark-submit:"
docker exec -i spark-master bash -lc "$SPARK_SUBMIT --version 2>&1 | head -n 1"

# Find examples JAR and run SparkPi
JAR_PATH=$(docker exec -i spark-master bash -lc 'ls /opt/bitnami/spark/examples/jars/spark-examples_*.jar 2>/dev/null | head -n 1')
if [[ -z "$JAR_PATH" ]]; then
  JAR_PATH=$(docker exec -i spark-master bash -lc 'find /opt/bitnami/spark -type f -name "spark-examples_*.jar" | head -n 1')
fi
[[ -n "$JAR_PATH" ]] || { echo "Could not locate spark-examples jar"; exit 1; }

echo "Submitting SparkPi..."
docker exec -i spark-master bash -lc "$SPARK_SUBMIT --master spark://spark-master:7077 --class org.apache.spark.examples.SparkPi \"$JAR_PATH\" 1000"
echo "SparkPi submitted. Check Master UI on :8080."
