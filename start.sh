#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

load_env() {
  local env_file="$1"
  [ -f "$env_file" ] || return 0

  while IFS= read -r line || [ -n "$line" ]; do
    line="${line#"${line%%[![:space:]]*}"}"
    line="${line%"${line##*[![:space:]]}"}"
    [ -z "$line" ] && continue
    [ "${line:0:1}" = "#" ] && continue
    [[ "$line" != *=* ]] && continue

    local key="${line%%=*}"
    local value="${line#*=}"
    key="${key%"${key##*[![:space:]]}"}"
    value="${value#"${value%%[![:space:]]*}"}"
    value="${value%"${value##*[![:space:]]}"}"

    if [[ "$value" == \"*\" && "$value" == *\" ]]; then
      value="${value:1:${#value}-2}"
    elif [[ "$value" == \'*\' && "$value" == *\' ]]; then
      value="${value:1:${#value}-2}"
    fi

    if [ -z "${!key+x}" ]; then
      export "$key=$value"
    fi
  done < "$env_file"
}

normalize_yes_no() {
  local value="${1:-}"
  local default_value="${2:-yes}"
  case "${value,,}" in
    y|yes|true|1) printf '%s\n' "yes" ;;
    n|no|false|0) printf '%s\n' "no" ;;
    *) printf '%s\n' "$default_value" ;;
  esac
}

get_dotenv_value() {
  local env_file="$1"
  local target_key="$2"
  [ -f "$env_file" ] || return 1

  while IFS= read -r line || [ -n "$line" ]; do
    line="${line#"${line%%[![:space:]]*}"}"
    line="${line%"${line##*[![:space:]]}"}"
    [ -z "$line" ] && continue
    [ "${line:0:1}" = "#" ] && continue
    [[ "$line" != *=* ]] && continue

    local key="${line%%=*}"
    local value="${line#*=}"
    key="${key%"${key##*[![:space:]]}"}"
    value="${value#"${value%%[![:space:]]*}"}"
    value="${value%"${value##*[![:space:]]}"}"

    if [ "$key" != "$target_key" ]; then
      continue
    fi

    if [[ "$value" == \"*\" && "$value" == *\" ]]; then
      value="${value:1:${#value}-2}"
    elif [[ "$value" == \'*\' && "$value" == *\' ]]; then
      value="${value:1:${#value}-2}"
    fi

    printf '%s\n' "$value"
    return 0
  done < "$env_file"

  return 1
}

get_ngrok_url() {
  local ngrok_json
  ngrok_json="$(curl -s http://127.0.0.1:4040/api/tunnels 2>/dev/null || true)"
  [ -n "$ngrok_json" ] || return 0

  if command -v python3 >/dev/null 2>&1; then
    printf '%s' "$ngrok_json" | python3 -c "import sys, json; data = json.load(sys.stdin); tunnels = data.get('tunnels', []); print(tunnels[0]['public_url'] if tunnels else '')" 2>/dev/null || true
    return 0
  fi

  if command -v jq >/dev/null 2>&1; then
    printf '%s' "$ngrok_json" | jq -r '.tunnels[0].public_url // empty' 2>/dev/null || true
    return 0
  fi
}

load_env ".env"

MODEL="${MODEL:-llama3.2:3b}"
USE_GPU="$(normalize_yes_no "${USE_GPU:-yes}" yes)"
USE_NGROK="$(normalize_yes_no "${USE_NGROK:-yes}" yes)"
VIRTEEM_TOKEN_VALUE="$(get_dotenv_value ".env" "VIRTEEM_TOKEN" || true)"

if ! command -v docker >/dev/null 2>&1; then
  echo "ERROR: Docker is not installed."
  exit 1
fi

if [ "$USE_NGROK" = "yes" ]; then
  if [ -z "${NGROK_AUTHTOKEN:-}" ]; then
    echo "ERROR: NGROK_AUTHTOKEN is required when USE_NGROK=yes."
    exit 1
  fi

  if [ -z "$VIRTEEM_TOKEN_VALUE" ]; then
    if command -v openssl >/dev/null 2>&1; then
      VIRTEEM_TOKEN_VALUE="$(openssl rand -hex 32)"
    else
      VIRTEEM_TOKEN_VALUE="$(python3 - <<'PY'
import secrets
print(secrets.token_hex(32))
PY
)"
    fi
  fi

  cat > ngrok-config.yml <<EOF
version: 2
authtoken: ${NGROK_AUTHTOKEN}
tunnels:
  ollama:
    addr: ollama:11434
    proto: http
    traffic_policy:
      on_http_request:
        - expressions:
            - "!( 'x-virteem-token' in req.headers ) || req.headers['x-virteem-token'][0] != '${VIRTEEM_TOKEN_VALUE}'"
          actions:
            - type: custom-response
              config:
                status_code: 403
                content: Unauthorized - Invalid Virteem token
EOF
fi

compose_args=(-f docker-compose.yml)
if [ "$USE_GPU" = "yes" ]; then
  compose_args+=(-f docker-compose.gpu.yml)
fi

echo ""
echo "Starting services..."
echo "  Model:  $MODEL"
echo "  GPU:    $USE_GPU"
echo "  Ngrok:  $USE_NGROK"
echo ""

if [ "$USE_NGROK" = "yes" ]; then
  docker compose "${compose_args[@]}" up -d ollama
else
  docker compose "${compose_args[@]}" up -d
fi

OLLAMA_CONTAINER=""
for _ in $(seq 1 30); do
  OLLAMA_CONTAINER="$(docker compose "${compose_args[@]}" ps -q ollama 2>/dev/null || true)"
  if [ -n "$OLLAMA_CONTAINER" ]; then
    break
  fi
  sleep 2
done

if [ -z "$OLLAMA_CONTAINER" ]; then
  echo "ERROR: Unable to retrieve the Ollama container."
  exit 1
fi

echo "Waiting for the Ollama service..."
for _ in $(seq 1 90); do
  if docker exec "$OLLAMA_CONTAINER" ollama list >/dev/null 2>&1; then
    break
  fi
  sleep 2
done

if ! docker exec "$OLLAMA_CONTAINER" ollama list >/dev/null 2>&1; then
  echo "ERROR: Ollama did not become available in time."
  exit 1
fi

echo "Pulling model: $MODEL"
docker exec "$OLLAMA_CONTAINER" ollama pull "$MODEL"

if [ "$USE_NGROK" = "yes" ]; then
  docker compose "${compose_args[@]}" --profile tunnel up -d --force-recreate ngrok
  echo "Retrieving the Ngrok URL..."
  NGROK_URL=""
  for _ in $(seq 1 30); do
    NGROK_URL="$(get_ngrok_url)"
    if [ -n "$NGROK_URL" ]; then
      break
    fi
    sleep 2
  done

  if [ -z "$NGROK_URL" ]; then
    echo "ERROR: Ngrok is not reachable at http://127.0.0.1:4040, or neither python3 nor jq is available to parse the tunnel URL."
    exit 1
  fi

  echo "============================================================"
  echo ""
  echo "  VIRTEEM LOCAL LLM - READY"
  echo ""
  echo "  Server URL:         $NGROK_URL"
  echo "  Virteem Token:      $VIRTEEM_TOKEN_VALUE"
  echo "  Model:              $MODEL"
  echo ""
  echo "  Please paste these values into:"
  echo "  Virteem Companion > Inference > Models > Local / Open Source"
  echo ""
  echo "============================================================"
  echo ""
  echo "  Dashboard Ngrok:    http://127.0.0.1:4040"
  echo "  Stop:               docker compose ${compose_args[*]} --profile tunnel down"
  echo "  Logs:               docker compose ${compose_args[*]} logs -f"
  echo ""
else
  echo "============================================================"
  echo ""
  echo "  VIRTEEM LOCAL LLM - READY"
  echo ""
  echo "  Local URL:          http://127.0.0.1:11434"
  echo "  Model:              $MODEL"
  echo ""
  echo "  Please use this URL in Virteem Companion for local-only usage."
  echo ""
  echo "============================================================"
  echo ""
  echo "  Stop:               docker compose ${compose_args[*]} down"
  echo "  Logs:               docker compose ${compose_args[*]} logs -f"
  echo ""
fi
