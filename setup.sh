#!/usr/bin/env bash
set -euo pipefail

ENV_FILE="${ENV_FILE:-.env}"
EXAMPLE_CANDIDATES=(".env.example" "example.env")
BACKUP_SUFFIX="$(date +%Y%m%d-%H%M%S)"
MODE="interactive" # or "ci"

usage() {
  cat <<EOF
Usage: ${0##*/} [--ci] [--env-file PATH]
  --ci              Non-interactive: exit 1 if any required vars are missing
  --env-file PATH   Path to .env file (default: .env)
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --ci) MODE="ci"; shift ;;
    --env-file) ENV_FILE="$2"; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Unknown arg: $1" >&2; usage; exit 2 ;;
  esac
done

# Find an example file if present
EXAMPLE_FILE=""
for cand in "${EXAMPLE_CANDIDATES[@]}"; do
  [[ -f "$cand" ]] && { EXAMPLE_FILE="$cand"; break; }
done

# Ensure .env exists (seed from example if possible)
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

# Ensure .env is ignored by git
if [[ -d .git ]]; then
  if [[ ! -f .gitignore ]] || ! grep -qxF "$(basename "$ENV_FILE")" .gitignore; then
    echo "[info] Adding $(basename "$ENV_FILE") to .gitignore"
    echo "$(basename "$ENV_FILE")" >> .gitignore
  fi
fi

# Helpers to parse KEY=VALUE lines, ignoring comments/blank
is_assignment() {
  [[ "$1" =~ ^[[:space:]]*[A-Za-z_][A-Za-z0-9_]*= ]]
}

key_from_line() {
  # prints KEY for KEY=VALUE (handles spaces before KEY)
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
  # Always write quoted to be safe (preserve spaces/specials)
  local v="$1"
  printf '"%s"' "$(printf '%s' "$v" | sed 's/"/\\"/g')"
}

# Build a map of defaults from example file (if present)
declare -A DEFAULTS
if [[ -n "$EXAMPLE_FILE" ]]; then
  while IFS= read -r line || [[ -n "$line" ]]; do
    is_assignment "$line" || continue
    k="$(key_from_line "$line")"
    rawv="$(val_from_line "$line")"
    DEFAULTS["$k"]="$(strip_quotes "$rawv")"
  done < "$EXAMPLE_FILE"
fi

# Build a set of keys we should manage:
# union of keys from example file and current env file
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

# Read current values from .env
declare -A CURRENT
while IFS= read -r line || [[ -n "$line" ]]; do
  is_assignment "$line" || continue
  k="$(key_from_line "$line")"
  rawv="$(val_from_line "$line")"
  CURRENT["$k"]="$(strip_quotes "$rawv")"
done < "$ENV_FILE"

# Function to maybe auto-generate secrets if key name matches pattern
maybe_generate_secret() {
  local key="$1"
  if [[ "$key" =~ (SECRET|TOKEN|KEY|PASSWORD|PASS|API_KEY)$ ]]; then
    # 32 random base64 chars (no newlines)
    openssl rand -base64 32 | tr -d '\n'
  fi
}

# Interactive fill of missing/empty vars
missing=()
declare -A UPDATED
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
    if [[ -n "$def" ]]; then
      echo "  default from $(basename "$EXAMPLE_FILE"): '$def'"
    fi

    # Offer auto-gen for secretish keys
    auto=""
    gen=""
    if gen="$(maybe_generate_secret "$k" 2>/dev/null || true)"; then
      if [[ -n "$gen" ]]; then
        auto="$gen"
      fi
    fi

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

# If nothing changed and nothing missing, we're done
if [[ ${#UPDATED[@]} -eq 0 ]]; then
  echo "[ok] $ENV_FILE is complete. No changes needed."
  exit 0
fi

# Write updated .env preserving comments & order.
tmp="$(mktemp)"
# First pass: rewrite existing lines with updated values
while IFS= read -r line || [[ -n "$line" ]]; do
  if is_assignment "$line"; then
    k="$(key_from_line "$line")"
    if [[ -n "${UPDATED[$k]:-}" ]]; then
      printf '%s=%s\n' "$k" "$(escape_val "${CURRENT[$k]}")" >> "$tmp"
      unset 'UPDATED[$k]'
    else
      # Keep original line
      printf '%s\n' "$line" >> "$tmp"
    fi
  else
    printf '%s\n' "$line" >> "$tmp"
  fi
done < "$ENV_FILE"

# Second pass: append any new keys (from example) that weren't in .env
if [[ ${#UPDATED[@]} -gt 0 ]]; then
  echo "" >> "$tmp"
  echo "# --- Added by setup on ${BACKUP_SUFFIX} ---" >> "$tmp"
  for k in "${!UPDATED[@]}"; do
    printf '%s=%s\n' "$k" "$(escape_val "${CURRENT[$k]}")" >> "$tmp"
  done
fi

# Backup and replace
cp "$ENV_FILE" "${ENV_FILE}.bak.${BACKUP_SUFFIX}"
mv "$tmp" "$ENV_FILE"

echo
echo "[ok] Updated $ENV_FILE"
echo "     Backup saved to ${ENV_FILE}.bak.${BACKUP_SUFFIX}"

# Final check: report any remaining empties (should be none)
empties=()
while IFS= read -r line || [[ -n "$line" ]]; do
  is_assignment "$line" || continue
  k="$(key_from_line "$line")"
  v="$(strip_quotes "$(val_from_line "$line")")"
  [[ -z "$v" ]] && empties+=("$k")
done < "$ENV_FILE"

if [[ ${#empties[@]} -eq 0 ]]; then
  echo "[done] All variables have values."
else
  echo "[warn] Some variables are still empty:" >&2
  for k in "${empties[@]}"; do echo "  - $k" >&2; done
  exit 1
fi
