#!/usr/bin/env bash
set -euo pipefail

ES_HOST="${ES_HOST:-http://127.0.0.1:9200}"
DOCS="${DOCS:-200000}"
DIMS="${DIMS:-128}"

echo "[ES] Criando índice 'logs' (${DIMS}D dense_vector)..."
curl -fS "${ES_HOST}/logs" -H 'Content-Type: application/json' -d "{
  \"mappings\": { \"properties\": {
    \"@timestamp\":{\"type\":\"date\"},
    \"service\":{\"type\":\"keyword\"},
    \"level\":{\"type\":\"keyword\"},
    \"message\":{\"type\":\"text\"},
    \"req_id\":{\"type\":\"keyword\"},
    \"latency_ms\":{\"type\":\"integer\"},
    \"embedding\":{\"type\":\"dense_vector\", \"dims\": ${DIMS}}
  }}}"

echo
echo "[ES] Gerando ${DOCS} docs (via container python) e fazendo bulk..."
docker run --rm -i -e DOCS -e DIMS python:3.11 python - <<'PY' | \
  curl -fS -H 'Content-Type: application/x-ndjson' -XPOST "${ES_HOST}/logs/_bulk" --data-binary @- > /tmp/es_bulk_resp.json
import json, random, datetime, os, sys
DOCS=int(os.environ.get("DOCS","200000"))
DIMS=int(os.environ.get("DIMS","128"))
services=["api-gateway","checkout","payment","auth","catalog"]
for i in range(DOCS):
    doc={
      "@timestamp": (datetime.datetime.utcnow()-datetime.timedelta(seconds=random.randint(0,172800))).isoformat()+"Z",
      "service": random.choice(services),
      "level": random.choice(["INFO","WARN","ERROR"]),
      "message": f"event {i}",
      "req_id": f"id{i}",
      "latency_ms": random.randint(1,2500),
      "embedding": [random.uniform(-1,1) for _ in range(DIMS)]
    }
    sys.stdout.write('{"index":{}}\n')
    sys.stdout.write(json.dumps(doc)+'\n')
PY

# Verifica se o bulk teve errors=false
if grep -q '"errors":\s*true' /tmp/es_bulk_resp.json; then
  echo "[ES] ERRO no bulk:"
  cat /tmp/es_bulk_resp.json | head -n 40
  exit 1
fi

curl -fS "${ES_HOST}/_refresh" > /dev/null
echo "[ES] Count:"
curl -fS -s "${ES_HOST}/logs/_count?pretty"
