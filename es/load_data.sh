#!/usr/bin/env bash
set -euo pipefail

ES_HOST="${ES_HOST:-http://localhost:${ES_HTTP:-9200}}"
DOCS="${DOCS:-200000}"
DIMS="${DIMS:-128}"

echo "[ES] Criando índice 'logs' com dense_vector (${DIMS}D)..."
curl -s "${ES_HOST}/logs" -H 'Content-Type: application/json' -d "{
  \"mappings\": { \"properties\": {
    \"@timestamp\":{\"type\":\"date\"},
    \"service\":{\"type\":\"keyword\"},
    \"level\":{\"type\":\"keyword\"},
    \"message\":{\"type\":\"text\"},
    \"req_id\":{\"type\":\"keyword\"},
    \"latency_ms\":{\"type\":\"integer\"},
    \"embedding\":{\"type\":\"dense_vector\", \"dims\": ${DIMS}}
  }} }" > /dev/null

echo "[ES] Gerando ${DOCS} docs e fazendo bulk..."
python3 "$(dirname "$0")/../bench/gen_docs.py" --n "$DOCS" --dims "$DIMS" |   curl -s -H 'Content-Type: application/x-ndjson' -XPOST "${ES_HOST}/logs/_bulk" --data-binary @- > /dev/null

curl -s "${ES_HOST}/_refresh" > /dev/null
echo "[ES] Concluído."
