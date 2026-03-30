#!/bin/bash
set -e

MODEL="${MODEL:-llama3.1}"

# --- Check prerequisites ---
if [ -z "$NGROK_AUTHTOKEN" ]; then
  echo "ERREUR: NGROK_AUTHTOKEN non défini."
  echo "  Créez un compte gratuit sur https://ngrok.com et récupérez votre token."
  echo ""
  echo "Usage:"
  echo "  NGROK_AUTHTOKEN=xxx MODEL=llama3.1 ./start.sh"
  exit 1
fi

if ! command -v docker &> /dev/null; then
  echo "ERREUR: Docker n'est pas installé."
  exit 1
fi

# --- Generate security token ---
if [ -z "$VIRTEEM_TOKEN" ]; then
  VIRTEEM_TOKEN=$(openssl rand -hex 32)
fi

# --- Generate ngrok config with traffic policy ---
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
            - "req.headers['x-virteem-token'][0] != '${VIRTEEM_TOKEN}'"
          actions:
            - type: custom-response
              config:
                status_code: 403
                content: Unauthorized - Invalid Virteem token
EOF

# --- Launch Docker Compose ---
MODEL="$MODEL" docker compose up -d

echo ""
echo "Démarrage en cours..."
echo "  Modèle: $MODEL"
echo "  Le téléchargement du modèle peut prendre plusieurs minutes."
echo ""
echo "Suivi du téléchargement:"
echo "  docker compose logs -f model-loader"
echo ""

# --- Wait for ngrok to be ready ---
NGROK_URL=""
for i in $(seq 1 30); do
  NGROK_URL=$(curl -s http://localhost:4040/api/tunnels 2>/dev/null | python3 -c "import sys,json; t=json.load(sys.stdin).get('tunnels',[]); print(t[0]['public_url'] if t else '')" 2>/dev/null || true)
  if [ -n "$NGROK_URL" ]; then break; fi
  sleep 2
done

if [ -z "$NGROK_URL" ]; then
  echo "En attente de Ngrok... Vérifiez votre NGROK_AUTHTOKEN si cela prend trop longtemps."
  echo "Dashboard Ngrok: http://localhost:4040"
  exit 1
fi

echo "============================================================"
echo ""
echo "  VIRTEEM LOCAL LLM - PRÊT"
echo ""
echo "  URL du serveur:     $NGROK_URL"
echo "  Token de sécurité:  $VIRTEEM_TOKEN"
echo "  Modèle:             $MODEL"
echo ""
echo "  Collez ces informations dans:"
echo "  Virteem Companion > Inférence > Modèles > Local / Open Source"
echo ""
echo "============================================================"
echo ""
echo "  Dashboard Ngrok:    http://localhost:4040"
echo "  Arrêter:            docker compose down"
echo "  Logs:               docker compose logs -f"
echo ""
