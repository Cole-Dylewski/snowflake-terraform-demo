#!/usr/bin/env bash
set -euo pipefail

# ================= Config / Flags =================
ENV_FILE="${ENV_FILE:-.env}"
EXAMPLE_CANDIDATES=(".env.example" "example.env")
BACKUP_SUFFIX="$(date +%Y%m%d-%H%M%S)"
MODE="interactive"   # or "ci"
TFVARS_OUT="infra/docker/env.auto.tfvars.json"
APPLY="no"           # "yes" to run terraform automatically

usage() {
  cat <<EOF
Usage: ${0##*/} [--ci] [--env-file PATH] [--tfvars-out PATH] [--apply]
  --ci                Non-interactive; exit 1 if any required vars are missing
  --env-file PATH     Path to .env file (default: .env or \$ENV_FILE)
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

# ================ Example discovery =================
EXAMPLE_FILE=""
for cand in "${EXAMPLE_CANDIDATES[@]}"; do
  [[ -f "$cand" ]] && { EXAMPLE_FILE="$cand"; break; }
done

# ================ Ensure .env exists =================
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

# ================ .gitignore safety =================
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

# ===================== Helpers ======================
is_assignment() { [[ "$1" =~ ^[[:space:]]*[A-Za-z_][A-Za-z0-9_]*= ]]; }
key_from_line() { local line="$1"; line="${line#"${line%%[![:space:]]*}"}"; echo "${line%%=*}"; }
val_from_line() { local line="$1"; echo "${line#*=}"; }
strip_quotes() {
  local v="$1"
  if   [[ "$v" =~ ^\".*\"$ ]]; then printf '%s' "${v:1:${#v}-2}"
  elif [[ "$v" =~ ^\'.*\'$ ]]; then printf '%s' "${v:1:${#v}-2}"
  else printf '%s' "$v"; fi
}
escape_val() { printf '"%s"' "$(printf '%s' "$1" | sed 's/\"/\\\"/g')"; }


need_cmd() { command -v "$1" >/dev/null 2>&1 || { echo "Missing: $1" >&2; return 1; }; }

echo "==> Preflight checks"
need_cmd docker
need_cmd terraform
need_cmd curl

# jq (Debian/RPi path)
if ! command -v jq >/dev/null 2>&1; then
  echo "Installing jq (requires sudo)..."
  if grep -qi "debian\|ubuntu\|raspbian" /etc/os-release; then
    sudo apt-get update -y && sudo apt-get install -y jq
  else
    echo "Please install jq manually for your OS." >&2
    exit 1
  fi
fi

# Validate Terraform version if you want a floor:
TF_MIN="1.7.0"
if ! printf '%s\n%s\n' "$TF_MIN" "$(terraform version -json | jq -r .terraform_version)" \
  | sort -VC 2>/dev/null; then
  echo "Terraform must be >= $TF_MIN" >&2
  exit 1
fi

# ============== Build defaults (from example) ===============
declare -A DEFAULTS
if [[ -n "$EXAMPLE_FILE" ]]; then
  while IFS= read -r line || [[ -n "$line" ]]; do
    is_assignment "$line" || continue
    k="$(key_from_line "$line")"
    rawv="$(val_from_line "$line")"
    DEFAULTS["$k"]="$(strip_quotes "$rawv")"
  done < "$EXAMPLE_FILE"
fi

# ================= Build full key set =================
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

# ================= Read current values =================
declare -A CURRENT
while IFS= read -r line || [[ -n "$line" ]]; do
  is_assignment "$line" || continue
  k="$(key_from_line "$line")"
  rawv="$(val_from_line "$line")"
  CURRENT["$k"]="$(strip_quotes "$rawv")"
done < "$ENV_FILE"

# Track updates
declare -A UPDATED=()

# ===== Airflow: auto-generate admin & fernet if missing =====
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

if [[ -z "${CURRENT["AIRFLOW_FERNET_KEY"]:-}" || "${CURRENT["AIRFLOW_FERNET_KEY"]}" == "auto" ]]; then
  if command -v python3 >/dev/null 2>&1; then
    CURRENT["AIRFLOW_FERNET_KEY"]="$(python3 - <<'PY'
import os, base64
print(base64.urlsafe_b64encode(os.urandom(32)).decode())
PY
)"
  else
    if command -v openssl >/dev/null 2>&1; then
      CURRENT["AIRFLOW_FERNET_KEY"]="$(openssl rand 32 | base64 | tr '+/' '-_' | tr -d '=')"
    else
      CURRENT["AIRFLOW_FERNET_KEY"]="$(head -c 32 /dev/urandom | base64 | tr '+/' '-_' | tr -d '=')"
    fi
  fi
  UPDATED["AIRFLOW_FERNET_KEY"]="${CURRENT["AIRFLOW_FERNET_KEY"]}"
  echo "[info] Generated AIRFLOW_FERNET_KEY"
fi

: "${CURRENT["AIRFLOW_ADMIN_USERNAME"]:=admin}"
: "${CURRENT["AIRFLOW_ADMIN_EMAIL"]:=admin@example.com}"
: "${CURRENT["AIRFLOW_ADMIN_FIRSTNAME"]:=Admin}"
: "${CURRENT["AIRFLOW_ADMIN_LASTNAME"]:=User}"
UPDATED["AIRFLOW_ADMIN_USERNAME"]="${CURRENT["AIRFLOW_ADMIN_USERNAME"]}"
UPDATED["AIRFLOW_ADMIN_EMAIL"]="${CURRENT["AIRFLOW_ADMIN_EMAIL"]}"
UPDATED["AIRFLOW_ADMIN_FIRSTNAME"]="${CURRENT["AIRFLOW_ADMIN_FIRSTNAME"]}"
UPDATED["AIRFLOW_ADMIN_LASTNAME"]="${CURRENT["AIRFLOW_ADMIN_LASTNAME"]}"

# ========== Helper to maybe autogenerate misc secrets ==========
maybe_generate_secret() {
  local key="$1"
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

# ========== Interactive fill / CI check for missing ==========
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
        if [[ -n "$def" ]]; then ans="$def"; else echo "  Value cannot be empty."; continue; fi
      elif [[ "$ans" == "!" && -n "$auto" ]]; then
        ans="$auto"; echo "  Generated secure value."
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

# ================= Rewrite .env if needed =================
for k in "AIRFLOW_ADMIN_USERNAME" "AIRFLOW_ADMIN_PASSWORD" "AIRFLOW_ADMIN_EMAIL" \
         "AIRFLOW_ADMIN_FIRSTNAME" "AIRFLOW_ADMIN_LASTNAME" "AIRFLOW_FERNET_KEY"; do
  ALL_KEYS["$k"]=1
done

needs_write=false
[[ ${#UPDATED[@]} -gt 0 ]] && needs_write=true

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

  # cp "$ENV_FILE" "${ENV_FILE}.bak.${BACKUP_SUFFIX}"
  mv "$tmp" "$ENV_FILE"

  echo ""
  echo "[ok] Updated $ENV_FILE"
  # echo "     Backup saved to ${ENV_FILE}.bak.${BACKUP_SUFFIX}"
else
  echo "[ok] $ENV_FILE is complete. No changes needed."
fi

# ============== Final empty check (warn only) ==============
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

# ============== Emit / upsert tfvars JSON for Terraform ==============
mkdir -p "$(dirname "$TFVARS_OUT")"
[[ -f "$TFVARS_OUT" ]] || echo '{}' > "$TFVARS_OUT"

# Export Airflow vars for Python step
export AIRFLOW_ADMIN_USERNAME="${CURRENT["AIRFLOW_ADMIN_USERNAME"]}"
export AIRFLOW_ADMIN_PASSWORD="${CURRENT["AIRFLOW_ADMIN_PASSWORD"]}"
export AIRFLOW_ADMIN_EMAIL="${CURRENT["AIRFLOW_ADMIN_EMAIL"]}"
export AIRFLOW_ADMIN_FIRSTNAME="${CURRENT["AIRFLOW_ADMIN_FIRSTNAME"]}"
export AIRFLOW_ADMIN_LASTNAME="${CURRENT["AIRFLOW_ADMIN_LASTNAME"]}"
export AIRFLOW_FERNET_KEY="${CURRENT["AIRFLOW_FERNET_KEY"]}"

# Export Spark/Jupyter/MinIO for env map
export SPARK_WORKER_COUNT="${CURRENT["SPARK_WORKER_COUNT"]:-}"
export SPARK_WORKER_CORES="${CURRENT["SPARK_WORKER_CORES"]:-}"
export SPARK_WORKER_MEMORY="${CURRENT["SPARK_WORKER_MEMORY"]:-}"
export JUPYTER_TOKEN="${CURRENT["JUPYTER_TOKEN"]:-}"
export JUPYTER_PORT="${CURRENT["JUPYTER_PORT"]:-}"
export SPARK_MASTER_UI_PORT="${CURRENT["SPARK_MASTER_UI_PORT"]:-}"
export SPARK_MASTER_PORT="${CURRENT["SPARK_MASTER_PORT"]:-}"
export SPARK_HISTORY_PORT="${CURRENT["SPARK_HISTORY_PORT"]:-}"
# Ensure numeric; remove inline comments in .env
export SPARK_WORKER_UI_BASE="${CURRENT["SPARK_WORKER_UI_BASE"]:-}"

export ENABLE_MINIO="${CURRENT["ENABLE_MINIO"]:-}"
export MINIO_ROOT_USER="${CURRENT["MINIO_ROOT_USER"]:-}"
export MINIO_ROOT_PASSWORD="${CURRENT["MINIO_ROOT_PASSWORD"]:-}"
export MINIO_API_PORT="${CURRENT["MINIO_API_PORT"]:-}"
export MINIO_CONSOLE_PORT="${CURRENT["MINIO_CONSOLE_PORT"]:-}"

python3 - "$TFVARS_OUT" <<'PY'
import json, os, sys
path = sys.argv[1]
try:
    with open(path) as f:
        data = json.load(f)
except Exception:
    data = {}

# 1) Root-level snake_case vars used by Terraform modules
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

# 2) Module-wide env map for spark_cluster
env_keys = [
    'SPARK_WORKER_COUNT', 'SPARK_WORKER_CORES', 'SPARK_WORKER_MEMORY',
    'JUPYTER_TOKEN', 'JUPYTER_PORT',
    'SPARK_MASTER_UI_PORT', 'SPARK_MASTER_PORT', 'SPARK_HISTORY_PORT',
    'SPARK_WORKER_UI_BASE',
    'ENABLE_MINIO', 'MINIO_ROOT_USER', 'MINIO_ROOT_PASSWORD',
    'MINIO_API_PORT', 'MINIO_CONSOLE_PORT',
]

env_map = {k: os.environ.get(k) for k in env_keys if os.environ.get(k)}
if env_map:
    if not isinstance(data.get('env'), dict):
        data['env'] = {}
    for k, v in env_map.items():
        if data['env'].get(k) != v:
            data['env'][k] = v
            changed = True

if changed:
    with open(path, 'w') as f:
        json.dump(data, f, indent=2)
    print(f"[ok] Wrote tfvars: {path}")
else:
    print(f"[ok] tfvars up-to-date: {path}")
PY

# Optional: JSON validation
if command -v jq >/dev/null 2>&1; then
  jq -e . "$TFVARS_OUT" >/dev/null && echo "[ok] tfvars JSON validated with jq"
fi

# ================= Terraform apply (optional) =================
if [[ "$APPLY" == "yes" ]]; then
  if [[ ! -d infra/docker ]]; then
    echo "[error] Expected terraform dir infra/docker not found" >&2; exit 1
  fi
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
# ================= Healthchecks & URL tests =================
run_healthchecks() {
  echo
  echo "===================="
  echo " Healthchecks"
  echo "===================="
  ok=0; fail=0

  http_ok() { # url label
    local url="$1" label="${2:-$1}" code
    # Treat any 2xx/3xx as success (Airflow redirects / -> /home with 302)
    code="$(curl -fsS -o /dev/null -w '%{http_code}' --max-time 8 --connect-timeout 3 "$url" || echo 000)"
    if [[ "$code" =~ ^(2|3)[0-9]{2}$ ]]; then
      printf '✅  %-35s %s\n' "$label" "$url"; ((ok++))
    else
      printf '❌  %-35s %s  (http %s)\n' "$label" "$url" "$code"; ((fail++))
    fi
  }

  tcp_ok() { # host port label
    local host="$1" port="$2" label="${3:-$host:$port}"
    if (exec 3<>/dev/tcp/"$host"/"$port") 2>/dev/null; then
      exec 3>&- 3<&-
      printf '✅  %-35s %s:%s\n' "$label" "$host" "$port"; ((ok++))
    else
      printf '❌  %-35s %s:%s (closed)\n' "$label" "$host" "$port"; ((fail++))
    fi
  }

  docker_has() { docker ps -q -f "name=^/$1$" -f "name=$1" >/dev/null; }

  airflow_port() {
    # Prefer Docker's published mapping first
    local p
    p="$(docker port airflow_web 8080/tcp 2>/dev/null | sed -E 's/.*:([0-9]+)$/\1/' | head -n1)"
    if [[ -n "$p" ]]; then echo "$p"; return 0; fi

    # Fallback guesses with multiple tools (in case ss isn't installed)
    for guess in 8099 8080; do
      if command -v ss >/dev/null 2>&1; then
        ss -ltn 2>/dev/null | awk '{print $4}' | grep -Eq "[:.]$guess\$" && { echo "$guess"; return 0; }
      elif command -v lsof >/dev/null 2>&1; then
        lsof -iTCP:"$guess" -sTCP:LISTEN >/dev/null 2>&1 && { echo "$guess"; return 0; }
      elif command -v netstat >/dev/null 2>&1; then
        netstat -lnt 2>/dev/null | awk '{print $4}' | grep -Eq "[:.]$guess\$" && { echo "$guess"; return 0; }
      fi
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
      curl -fsS -o /dev/null --max-time 3 "http://localhost:${AF_PORT}/health" >/dev/null 2>&1 \
        && printf '✅  %-35s %s\n' "Airflow /health" "http://localhost:${AF_PORT}/health" \
        || printf 'ℹ️   %-35s %s\n' "Airflow /health (optional)" "http://localhost:${AF_PORT}/health"
    else
      printf '❌  %-35s %s\n' "Airflow Web UI" "not detected"; ((fail++))
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
    tcp_ok  "127.0.0.1" 19092 "Kafka broker (TCP)"   # host mapping 19092 -> 9092
  else
    printf 'ℹ️   %-35s %s\n' "Redpanda Admin /ready" "container not running"
  fi

  echo
  echo "--------------------"
  echo "Summary: ${ok} OK, ${fail} failed"
  echo "--------------------"
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
