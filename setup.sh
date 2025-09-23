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

# ----------------- Airflow Fernet auto-generation -----------------
if [[ -z "${CURRENT["AIRFLOW_FERNET_KEY"]:-}" || "${CURRENT["AIRFLOW_FERNET_KEY"]}" == "auto" ]]; then
  if command -v python3 >/dev/null 2>&1; then
    _FERNET="$(python3 - <<'PY'
import os, base64
print(base64.urlsafe_b64encode(os.urandom(32)).decode())
PY
)"
  else
    # Fallback: 32 bytes urandom, urlsafe, strip padding
    if command -v openssl >/dev/null 2>&1; then
      _FERNET="$(openssl rand 32 | base64 | tr '+/' '-_' | tr -d '=')"
    else
      _FERNET="$(head -c 32 /dev/urandom | base64 | tr '+/' '-_' | tr -d '=')"
    fi
  fi

  CURRENT["AIRFLOW_FERNET_KEY"]="${_FERNET}"
  UPDATED["AIRFLOW_FERNET_KEY"]="${_FERNET}"
  echo "[info] Generated AIRFLOW_FERNET_KEY"
fi

# ----------------- Maybe auto-generate secrets -----------------
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
    # POSIX fallback
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

# ----------------- If no changes, exit early -----------------
if [[ ${#UPDATED[@]} -eq 0 ]]; then
  echo "[ok] $ENV_FILE is complete. No changes needed."
else
  # ----------------- Rewrite .env preserving comments/order -----------------
  tmp="$(mktemp)"
  while IFS= read -r line || [[ -n "$line" ]]; do
    if is_assignment "$line"; then
      k="$(key_from_line "$line")"
      if [[ -n "${UPDATED[$k]:-}" ]]; then
        printf '%s=%s\n' "$k" "$(escape_val "${CURRENT[$k]}")" >> "$tmp"
        unset 'UPDATED[$k]'
      else
  printf '%s\n' "" >> ""
fi
    else
      printf '%s\n' "$line" >> "$tmp"
    fi
  done < "$ENV_FILE"

  if [[ ${#UPDATED[@]} -gt 0 ]]; then
    echo "" >> "$tmp"
    echo "# --- Added by setup on ${BACKUP_SUFFIX} ---" >> "$tmp"
    for k in "${!UPDATED[@]}"; do
      printf '%s=%s\n' "$k" "$(escape_val "${CURRENT[$k]}")" >> "$tmp"
    done
  fi

  cp "$ENV_FILE" "${ENV_FILE}.bak.${BACKUP_SUFFIX}"
  mv "$tmp" "$ENV_FILE"

  echo
  echo "[ok] Updated $ENV_FILE"
  echo "     Backup saved to ${ENV_FILE}.bak.${BACKUP_SUFFIX}"
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

# ----------------- Emit tfvars JSON (for Terraform) -----------------
mkdir -p "$(dirname "$TFVARS_OUT")"
awk -F= '
  BEGIN { print "{"; first=1 }
  /^[[:space:]]*#/ { next }
  /^[[:space:]]*$/ { next }
  {
    key=$1; sub(/^[[:space:]]+|[[:space:]]+$/, "", key)
    $1=""
    val=substr($0,2); sub(/^[[:space:]]+/, "", val)

    # strip surrounding single/double quotes if present
    if (val ~ /^".*"$/ || val ~ /^'"'"'.*'"'"'$/) { val=substr(val,2,length(val)-2) }

    gsub(/"/, "\\\"", val)   # escape quotes
    if (!first) printf(",\n"); first=0
    printf("  \"%s\": \"%s\"", key, val)   # keys match .env; rename in TF if desired
  }
  END { print "\n}" }
' "$ENV_FILE" > "$TFVARS_OUT"

echo "[ok] Wrote tfvars: $TFVARS_OUT"

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
  echo "[info] Running terraform init/apply with -var-file=$TFVARS_OUT"
  terraform -chdir=infra/docker init -upgrade
  terraform -chdir=infra/docker apply -auto-approve -var-file="$TFVARS_OUT"
  echo "[done] Terraform apply complete."
else
  cat <<EONEXT

[next steps]
  # To apply with the generated tfvars:
  terraform -chdir=infra/docker init -upgrade
  terraform -chdir=infra/docker apply -auto-approve -var-file="$TFVARS_OUT"


EONEXT
fi
