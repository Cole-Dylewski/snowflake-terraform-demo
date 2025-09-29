#!/usr/bin/env bash
set -euo pipefail
URL="${1:?url required}"; TIMEOUT="${2:-60}"
echo "Waiting up to ${TIMEOUT}s for ${URL}..."
for i in $(seq 1 "$TIMEOUT"); do
  if curl -fsS "$URL" >/dev/null 2>&1; then
    echo "OK: ${URL}"
    exit 0
  fi
  sleep 1
done
echo "Timed out waiting for ${URL}" >&2
exit 1
