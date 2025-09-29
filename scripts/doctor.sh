#!/usr/bin/env bash
set -euo pipefail

echo "=== Doctor: tools ==="
for c in docker terraform curl jq; do
  command -v "$c" >/dev/null || { echo "Missing: $c"; exit 1; }
done

echo "=== Doctor: docker network ==="
docker info >/dev/null

echo "=== Doctor: terraform plan (dry run) ==="
terraform -chdir=infra/docker init -upgrade -input=false >/dev/null
terraform -chdir=infra/docker validate

echo "=== Doctor: containers up? ==="
docker ps --format 'table {{.Names}}\t{{.Image}}\t{{.Status}}'

echo "=== Doctor: smokes ==="
"$(dirname "$0")/smoke_all.sh"
