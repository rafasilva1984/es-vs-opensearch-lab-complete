#!/usr/bin/env bash
set -euo pipefail

OS_HOST="${OS_HOST:-http://localhost:${OS_HTTP:-9201}}"
DOCS="${DOCS:-200000}"
DIMS="${DIMS:-128}"

echo "[OS] Criando índice 'logs' com knn_vector (${DIMS}D)..."
curl -s "${OS_HOST}/logs" -H 'Content-Type: application/json' -d "{
  \"settings\":{\"index.knn\": true},
  \"mappings\":{ \"properties\": {
    \"@timestamp\":{\"type\":\"date\"},
    \"service\":{\"type\":\"keyword\"},
    \"level\":{\"type\":\"keyword\"},
    \"message\":{\"type\":\"text\"},
    \"req_id\":{\"type\":\"keyword\"},
    \"latency_ms\":{\"type\":\"integer\"},
    \"embedding\":{\"type\":\"knn_vector\", \"dimension\": ${DIMS},
      \"method\":{\"name\":\"hnsw\", \"engine\":\"nmslib\", \"space_type\":\"cosinesimil\"}}
  }} }" > /dev/null

echo "[OS] Gerando ${DOCS} docs e fazendo bulk..."
python3 "$(dirname "$0")/../bench/gen_docs.py" --n "$DOCS" --dims "$DIMS" |   curl -s -H 'Content-Type: application/x-ndjson' -XPOST "${OS_HOST}/logs/_bulk" --data-binary @- > /dev/null

curl -s "${OS_HOST}/_refresh" > /dev/null
echo "[OS] Concluído."
