#!/usr/bin/env bash
set -euo pipefail

# ----------------- Config / Flags -----------------
ENV_FILE="${ENV_FILE:-.env}"
EXAMPLE_CANDIDATES=(".env.example" "example.env")
BACKUP_SUFFIX="$(date +%Y%m%d-%H%M%S)"
MODE="interactive" # or "ci"
TFVARS_OUT="infra/docker/env.auto.tfvars.json"
APPLY="no"  # "yes" to run terraform

usage() {
  cat <<EOF
Usage: ${0##*/} [--ci] [--env-file PATH] [--tfvars-out PATH] [--apply]
  --ci                Non-interactive; exit 1 if any required vars are missing
  --env-file PATH     Path to .env file (default: .env or $ENV_FILE)
  --tfvars-out PATH   Where to write JSON tfvars (default: infra/docker/env.auto.tfvars.json)
  --apply             After updating .env and tfvars, run: terraform init/apply
  -h, --help          Show this help
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --ci) MODE="ci"; shift ;;
    --env-file) ENV_FILE="$2"; shift 2 ;;
    --tfvars-out) TFVARS_OUT="$2"; shift 2 ;;
    --apply) APPLY="yes"; shift ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Unknown arg: $1" >&2; usage; exit 2 ;;
  esac
done

# Require Bash >= 4 for associative arrays
if ! (exec bash -c '[[ ${BASH_VERSINFO[0]} -ge 4 ]]'); then
  echo "[error] Bash 4+ required (associative arrays). Current: $BASH_VERSION" >&2
  exit 1
fi

# ----------------- Example discovery -----------------
EXAMPLE_FILE=""
for cand in "${EXAMPLE_CANDIDATES[@]}"; do
  [[ -f "$cand" ]] && { EXAMPLE_FILE="$cand"; break; }
done

# ----------------- Ensure .env exists -----------------
if [[ ! -f "$ENV_FILE" ]]; then
  if [[ -n "$EXAMPLE_FILE" ]]; then
    echo "[info] $ENV_FILE not found. Seeding from $EXAMPLE_FILE"
    cp "$EXAMPLE_FILE" "$ENV_FILE"
  else
    echo "[info] $ENV_FILE not found. Creating a new one."
    cat > "$ENV_FILE" <<'EOF'
# Environment configuration
# KEY=VALUE
EOF
  fi
fi

# ----------------- .gitignore safety -----------------
if [[ -d .git ]]; then
  if [[ ! -f .gitignore ]] || ! grep -qxF "$(basename "$ENV_FILE")" .gitignore; then
    echo "[info] Adding $(basename "$ENV_FILE") to .gitignore"
    echo "$(basename "$ENV_FILE")" >> .gitignore
  fi
  if [[ ! -f .gitignore ]] || ! grep -qxF "$TFVARS_OUT" .gitignore; then
    echo "[info] Adding $TFVARS_OUT to .gitignore"
    echo "$TFVARS_OUT" >> .gitignore
  fi
fi

# ----------------- Helpers -----------------
is_assignment() { [[ "$1" =~ ^[[:space:]]*[A-Za-z_][A-Za-z0-9_]*= ]]; }

key_from_line() {
  local line="$1"
  line="${line#"${line%%[![:space:]]*}"}"   # ltrim
  echo "${line%%=*}"
}

val_from_line() {
  local line="$1"
  echo "${line#*=}"
}

strip_quotes() {
  local v="$1"
  if [[ "$v" =~ ^\".*\"$ ]]; then
    printf '%s' "${v:1:${#v}-2}"
  elif [[ "$v" =~ ^\'.*\'$ ]]; then
    printf '%s' "${v:1:${#v}-2}"
  else
    printf '%s' "$v"
  fi
}

escape_val() {
  # Always write quoted to preserve spaces/specials
  local v="$1"
  printf '"%s"' "$(printf '%s' "$v" | sed 's/"/\\"/g')"
}

# ----------------- Build defaults (from example) -----------------
declare -A DEFAULTS
if [[ -n "$EXAMPLE_FILE" ]]; then
  while IFS= read -r line || [[ -n "$line" ]]; do
    is_assignment "$line" || continue
    k="$(key_from_line "$line")"
    rawv="$(val_from_line "$line")"
    DEFAULTS["$k"]="$(strip_quotes "$rawv")"
  done < "$EXAMPLE_FILE"
fi

# ----------------- Build full key set -----------------
declare -A ALL_KEYS
while IFS= read -r line || [[ -n "$line" ]]; do
  is_assignment "$line" || continue
  k="$(key_from_line "$line")"
  ALL_KEYS["$k"]=1
done < "$ENV_FILE"

if [[ -n "$EXAMPLE_FILE" ]]; then
  while IFS= read -r line || [[ -n "$line" ]]; do
    is_assignment "$line" || continue
    k="$(key_from_line "$line")"
    ALL_KEYS["$k"]=1
  done < "$EXAMPLE_FILE"
fi

# ----------------- Read current values -----------------
declare -A CURRENT
while IFS= read -r line || [[ -n "$line" ]]; do
  is_assignment "$line" || continue
  k="$(key_from_line "$line")"
  rawv="$(val_from_line "$line")"
  CURRENT["$k"]="$(strip_quotes "$rawv")"
done < "$ENV_FILE"

# ----------------- Track updates (fix for nounset) -----------------
declare -A UPDATED=()

# ----------------- Airflow: auto-generate secrets (no prompts) -----------------
# Admin password (only if missing)
if [[ -z "${CURRENT["AIRFLOW_ADMIN_PASSWORD"]:-}" ]]; then
  if command -v python3 >/dev/null 2>&1; then
    CURRENT["AIRFLOW_ADMIN_PASSWORD"]="$(python3 - <<'PY'
import secrets, string
alphabet = string.ascii_letters + string.digits + '!@#%+='
print(''.join(secrets.choice(alphabet) for _ in range(24)))
PY
)"
  else
    CURRENT["AIRFLOW_ADMIN_PASSWORD"]="$(tr -dc 'A-Za-z0-9!@#%+=' </dev/urandom | head -c 24)"
  fi
  UPDATED["AIRFLOW_ADMIN_PASSWORD"]="${CURRENT["AIRFLOW_ADMIN_PASSWORD"]}"
  echo "[info] Generated AIRFLOW_ADMIN_PASSWORD"
fi

# Fernet key (urlsafe base64, 32 bytes)
if [[ -z "${CURRENT["AIRFLOW_FERNET_KEY"]:-}" || "${CURRENT["AIRFLOW_FERNET_KEY"]}" == "auto" ]]; then
  if command -v python3 >/dev/null 2>&1; then
    CURRENT["AIRFLOW_FERNET_KEY"]="$(python3 - <<'PY'
import os, base64
print(base64.urlsafe_b64encode(os.urandom(32)).decode())
PY
)"
  else
    # Fallback: urlsafe, strip padding
    if command -v openssl >/dev/null 2>&1; then
      CURRENT["AIRFLOW_FERNET_KEY"]="$(openssl rand 32 | base64 | tr '+/' '-_' | tr -d '=')"
    else
      CURRENT["AIRFLOW_FERNET_KEY"]="$(head -c 32 /dev/urandom | base64 | tr '+/' '-_' | tr -d '=')"
    fi
  fi
  UPDATED["AIRFLOW_FERNET_KEY"]="${CURRENT["AIRFLOW_FERNET_KEY"]}"
  echo "[info] Generated AIRFLOW_FERNET_KEY"
fi

# Ensure bootstrap identity defaults exist (can be overridden in .env later)
: "${CURRENT["AIRFLOW_ADMIN_USERNAME"]:=admin}"
: "${CURRENT["AIRFLOW_ADMIN_EMAIL"]:=admin@example.com}"
: "${CURRENT["AIRFLOW_ADMIN_FIRSTNAME"]:=Admin}"
: "${CURRENT["AIRFLOW_ADMIN_LASTNAME"]:=User}"
UPDATED["AIRFLOW_ADMIN_USERNAME"]="${CURRENT["AIRFLOW_ADMIN_USERNAME"]}"
UPDATED["AIRFLOW_ADMIN_EMAIL"]="${CURRENT["AIRFLOW_ADMIN_EMAIL"]}"
UPDATED["AIRFLOW_ADMIN_FIRSTNAME"]="${CURRENT["AIRFLOW_ADMIN_FIRSTNAME"]}"
UPDATED["AIRFLOW_ADMIN_LASTNAME"]="${CURRENT["AIRFLOW_ADMIN_LASTNAME"]}"

# ----------------- Maybe auto-generate secrets for other keys -----------------
maybe_generate_secret() {
  local key="$1"
  # Always return 0; echo empty if cannot generate
  if [[ "$key" =~ (SECRET|TOKEN|KEY|PASSWORD|PASS|API_KEY)$ ]]; then
    if command -v python3 >/dev/null 2>&1; then
      python3 - <<'PY' || true
import secrets, base64
print(base64.b64encode(secrets.token_bytes(32)).decode().strip())
PY
      return 0
    fi
    if command -v openssl >/dev/null 2>&1; then
      openssl rand -base64 32 2>/dev/null | tr -d '\n' || true
      return 0
    fi
    head -c 32 /dev/urandom | base64 | tr -d '\n' || true
    return 0
  fi
  return 0
}

# ----------------- Interactive fill / CI check -----------------
missing=()
for k in "${!ALL_KEYS[@]}"; do
  cur="${CURRENT[$k]:-}"
  if [[ -z "$cur" ]]; then
    def="${DEFAULTS[$k]:-}"
    if [[ "$MODE" == "ci" ]]; then
      missing+=("$k")
      continue
    fi

    echo
    echo "• $k is missing."
    [[ -n "$def" ]] && echo "  default from $(basename "$EXAMPLE_FILE"): '$def'"

    auto="$(maybe_generate_secret "$k" || true)"
    prompt="Enter value for $k"
    [[ -n "$def" ]] && prompt+=" [default: $def]"
    [[ -n "$auto" ]] && prompt+=" [autogen available: <enter> to accept default, or type '!' to autogen]"
    prompt+=": "

    while :; do
      read -r -p "$prompt" ans || true
      if [[ -z "$ans" ]]; then
        if [[ -n "$def" ]]; then
          ans="$def"
        else
          echo "  Value cannot be empty."
          continue
        fi
      elif [[ "$ans" == "!" && -n "$auto" ]]; then
        ans="$auto"
        echo "  Generated secure value."
      fi
      break
    done

    UPDATED["$k"]="$ans"
    CURRENT["$k"]="$ans"
  fi
done

if [[ "$MODE" == "ci" && ${#missing[@]} -gt 0 ]]; then
  echo "[error] Missing required env vars in $ENV_FILE:" >&2
  for k in "${missing[@]}"; do echo "  - $k" >&2; done
  exit 1
fi

# ----------------- If no changes, maybe still ensure tfvars -----------------
# We'll still re-emit tfvars below even if .env unchanged, so skip early exit.

# ----------------- Rewrite .env preserving comments/order -----------------
# Ensure any newly introduced keys (by this script) are part of ALL_KEYS
for k in "AIRFLOW_ADMIN_USERNAME" "AIRFLOW_ADMIN_PASSWORD" "AIRFLOW_ADMIN_EMAIL" \
         "AIRFLOW_ADMIN_FIRSTNAME" "AIRFLOW_ADMIN_LASTNAME" "AIRFLOW_FERNET_KEY"; do
  ALL_KEYS["$k"]=1
done

# Only rewrite when UPDATED contains something not already in the file as-is
needs_write=false
if [[ ${#UPDATED[@]} -gt 0 ]]; then
  needs_write=true
fi

if $needs_write; then
  tmp="$(mktemp)"
  while IFS= read -r line || [[ -n "$line" ]]; do
    if is_assignment "$line"; then
      k="$(key_from_line "$line")"
      if [[ -n "${CURRENT[$k]:-}" ]]; then
        printf '%s=%s\n' "$k" "$(escape_val "${CURRENT[$k]}")" >> "$tmp"
      else
        printf '%s\n' "$line" >> "$tmp"
      fi
    else
      printf '%s\n' "$line" >> "$tmp"
    fi
  done < "$ENV_FILE"

  # Append any keys that didn't exist previously
  to_append=()
  for k in "${!UPDATED[@]}"; do
    if ! grep -qE "^[[:space:]]*$k=" "$ENV_FILE"; then
      to_append+=("$k")
    fi
  done

  if [[ ${#to_append[@]} -gt 0 ]]; then
    echo "" >> "$tmp"
    echo "# --- Added by setup on ${BACKUP_SUFFIX} ---" >> "$tmp"
    for k in "${to_append[@]}"; do
      printf '%s=%s\n' "$k" "$(escape_val "${CURRENT[$k]}")" >> "$tmp"
    done
  fi

  cp "$ENV_FILE" "${ENV_FILE}.bak.${BACKUP_SUFFIX}"
  mv "$tmp" "$ENV_FILE"

  echo ""
  echo "[ok] Updated $ENV_FILE"
  echo "     Backup saved to ${ENV_FILE}.bak.${BACKUP_SUFFIX}"
else
  echo "[ok] $ENV_FILE is complete. No changes needed."
fi

# ----------------- Final empty check -----------------
empties=()
while IFS= read -r line || [[ -n "$line" ]]; do
  is_assignment "$line" || continue
  k="$(key_from_line "$line")"
  v="$(strip_quotes "$(val_from_line "$line")")"
  [[ -z "$v" ]] && empties+=("$k")
done < "$ENV_FILE"

if [[ ${#empties[@]} -gt 0 ]]; then
  echo "[warn] Some variables are still empty:" >&2
  for k in "${empties[@]}"; do echo "  - $k" >&2; done
  [[ "$MODE" == "ci" ]] && exit 1
fi

# ----------------- Emit / upsert tfvars JSON for Terraform -----------------
# Only write the vars Terraform expects (snake_case). Do not dump entire .env.
mkdir -p "$(dirname "$TFVARS_OUT")"
[[ -f "$TFVARS_OUT" ]] || echo '{}' > "$TFVARS_OUT"

# Export env so Python can see CURRENT values
export AIRFLOW_ADMIN_USERNAME="${CURRENT["AIRFLOW_ADMIN_USERNAME"]}"
export AIRFLOW_ADMIN_PASSWORD="${CURRENT["AIRFLOW_ADMIN_PASSWORD"]}"
export AIRFLOW_ADMIN_EMAIL="${CURRENT["AIRFLOW_ADMIN_EMAIL"]}"
export AIRFLOW_ADMIN_FIRSTNAME="${CURRENT["AIRFLOW_ADMIN_FIRSTNAME"]}"
export AIRFLOW_ADMIN_LASTNAME="${CURRENT["AIRFLOW_ADMIN_LASTNAME"]}"
export AIRFLOW_FERNET_KEY="${CURRENT["AIRFLOW_FERNET_KEY"]}"

python3 - "$TFVARS_OUT" <<'PY'
import json, os, sys
path = sys.argv[1]
try:
    with open(path) as f:
        data = json.load(f)
except Exception:
    data = {}

# Map .env (UPPER) -> Terraform vars (snake_case)
map_pairs = {
    'airflow_admin_username':  os.environ.get('AIRFLOW_ADMIN_USERNAME', 'admin'),
    'airflow_admin_password':  os.environ.get('AIRFLOW_ADMIN_PASSWORD', ''),
    'airflow_admin_email':     os.environ.get('AIRFLOW_ADMIN_EMAIL', 'admin@example.com'),
    'airflow_admin_firstname': os.environ.get('AIRFLOW_ADMIN_FIRSTNAME', 'Admin'),
    'airflow_admin_lastname':  os.environ.get('AIRFLOW_ADMIN_LASTNAME', 'User'),
    'airflow_fernet_key':      os.environ.get('AIRFLOW_FERNET_KEY', ''),
}

changed = False
for k, v in map_pairs.items():
    if v is not None and v != '':
        if data.get(k) != v:
            data[k] = v
            changed = True

if changed:
    with open(path, 'w') as f:
        json.dump(data, f, indent=2)
    print(f"[ok] Wrote tfvars: {path}")
else:
    print(f"[ok] tfvars up-to-date: {path}")
PY

# Optional: show a quick validation if jq exists
if command -v jq >/dev/null 2>&1; then
  jq -e . "$TFVARS_OUT" >/dev/null && echo "[ok] tfvars JSON validated with jq"
fi

# ----------------- Optional Terraform apply -----------------
if [[ "$APPLY" == "yes" ]]; then
  if [[ ! -d infra/docker ]]; then
    echo "[error] Expected terraform dir infra/docker not found" >&2
    exit 1
  fi
  # When using -chdir, the -var-file path must be relative to that dir (or absolute)
  TF_DIR="infra/docker"
  TFVARS_FOR_TF="$TFVARS_OUT"
  if [[ "$TFVARS_OUT" == "$TF_DIR/"* ]]; then
    TFVARS_FOR_TF="${TFVARS_OUT#${TF_DIR}/}"
  fi
  echo "[info] Running terraform init/apply with -var-file=$TFVARS_FOR_TF"
  terraform -chdir="$TF_DIR" init -upgrade
  terraform -chdir="$TF_DIR" apply -auto-approve -var-file="$TFVARS_FOR_TF"
  echo "[done] Terraform apply complete."
else
  cat <<EONEXT

[next steps]
  # To apply with the generated tfvars:
  terraform -chdir=infra/docker init -upgrade
  terraform -chdir=infra/docker apply -auto-approve -var-file="env.auto.tfvars.json"

EONEXT
fi
# ----------------- Healthchecks & Service URL tests -----------------
run_healthchecks() {
  echo
  echo "===================="
  echo " Healthchecks"
  echo "===================="

  ok=0; fail=0

  http_ok() { # url label
    local url="$1" label="${2:-$1}"
    local code
    code="$(curl -fsS -o /dev/null -w '%{http_code}' --max-time 5 "$url" || echo 000)"
    if [[ "$code" =~ ^2|^3 ]]; then
      printf '✅  %-35s %s\n' "$label" "$url"
      ((ok++))
    else
      printf '❌  %-35s %s  (http %s)\n' "$label" "$url" "$code"
      ((fail++))
    fi
  }

  tcp_ok() { # host port label
    local host="$1" port="$2" label="${3:-$host:$port}"
    if (exec 3<>/dev/tcp/"$host"/"$port") 2>/dev/null; then
      exec 3>&- 3<&-
      printf '✅  %-35s %s:%s\n' "$label" "$host" "$port"
      ((ok++))
    else
      printf '❌  %-35s %s:%s (closed)\n' "$label" "$host" "$port"
      ((fail++))
    fi
  }

  docker_has() { # name
    docker ps -q -f "name=^/$1$" -f "name=$1" >/dev/null
  }

  airflow_port() { # best-effort detect host->8080 map
    local p
    p="$(docker port airflow_web 8080/tcp 2>/dev/null | awk -F: 'NF{print $NF; exit}')"
    if [[ -n "$p" ]]; then echo "$p"; return 0; fi
    # fallbacks commonly used
    for guess in 8099 8080; do
      ss -ltn "sport = :$guess" >/dev/null 2>&1 && { echo "$guess"; return 0; }
    done
    return 1
  }

  echo "→ Nginx / FastAPI (via reverse proxy)"
  http_ok "http://localhost/"              "Nginx → FastAPI root"
  http_ok "http://localhost/docs"          "FastAPI docs (proxied)"

  echo
  echo "→ Database UIs"
  http_ok "http://localhost:8080/"         "pgAdmin"
  http_ok "http://localhost:8081/"         "pgweb (source)"
  http_ok "http://localhost:8082/"         "pgweb (destination)"

  echo
  echo "→ Spark & Jupyter"
  http_ok "http://localhost:9090/"         "Spark Master UI"
  http_ok "http://localhost:9091/"         "Spark Worker UI"
  http_ok "http://localhost:18080/"        "Spark History UI"
  http_ok "http://localhost:8889/"         "JupyterLab (may 302)"

  echo
  echo "→ Airflow (auto-detected port)"
  if docker_has airflow_web; then
    AF_PORT="$(airflow_port || true)"
    if [[ -n "${AF_PORT:-}" ]]; then
      http_ok "http://localhost:${AF_PORT}/"         "Airflow Web UI"
      # This endpoint may not exist; ignore failure
      curl -fsS -o /dev/null -w '' --max-time 3 "http://localhost:${AF_PORT}/health" >/dev/null 2>&1 \
        && printf '✅  %-35s %s\n' "Airflow /health" "http://localhost:${AF_PORT}/health" \
        || printf 'ℹ️   %-35s %s\n' "Airflow /health (optional)" "http://localhost:${AF_PORT}/health"
    else
      printf '❌  %-35s %s\n' "Airflow Web UI" "not detected"
      ((fail++))
    fi
  else
    printf 'ℹ️   %-35s %s\n' "Airflow Web UI" "container not running"
  fi

  echo
  echo "→ MinIO (S3-compatible)"
  http_ok "http://localhost:9000/minio/health/ready" "MinIO API /ready"
  http_ok "http://localhost:9000/minio/health/live"  "MinIO API /live"
  http_ok "http://localhost:9001/"                   "MinIO Console"

  echo
  echo "→ Kafka / Redpanda (optional)"
  if docker_has redpanda; then
    http_ok "http://localhost:9644/v1/status/ready"  "Redpanda Admin /ready"
    tcp_ok  "127.0.0.1" 9092 "Kafka broker (TCP)"
  else
    printf 'ℹ️   %-35s %s\n' "Redpanda Admin /ready" "container not running"
  fi

  echo
  echo "--------------------"
  echo "Summary: ${ok} OK, ${fail} failed"
  echo "--------------------"
  # Return non-zero if any failures
  [[ $fail -eq 0 ]]
}

# Auto-run healthchecks when --apply was used (after Terraform)
if [[ "${APPLY:-no}" == "yes" ]]; then
  echo
  echo "[info] Running post-apply healthchecks…"
  run_healthchecks || { echo '[warn] Some checks failed. Inspect containers and logs.' >&2; }
else
  echo
  echo "[hint] To run healthchecks now, re-run:"
  echo "       bash -lc 'source ./setup.sh; run_healthchecks'"
fi
