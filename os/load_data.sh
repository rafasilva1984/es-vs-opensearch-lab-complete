#!/usr/bin/env bash
set -euo pipefail

OS_HOST="${OS_HOST:-https://127.0.0.1:9201}"
OS_USER="${OS_USER:-admin}"
OS_PASS="${OS_PASS:-Admin123!ChangeMe}"
DOCS="${DOCS:-200000}"
DIMS="${DIMS:-128}"

# apaga índice antigo (ignora 404)
curl -fSk -u "${OS_USER}:${OS_PASS}" -XDELETE "${OS_HOST}/logs" >/dev/null || true

echo "[OS] Criando índice 'logs' (${DIMS}D knn_vector) em ${OS_HOST} ..."
curl -fSk -u "${OS_USER}:${OS_PASS}" -XPUT "${OS_HOST}/logs" -H 'Content-Type: application/json' -d "{
  \"settings\":{\"index.knn\": true},
  \"mappings\":{\"properties\": {
    \"@timestamp\":{\"type\":\"date\"},
    \"service\":{\"type\":\"keyword\"},
    \"level\":{\"type\":\"keyword\"},
    \"message\":{\"type\":\"text\"},
    \"req_id\":{\"type\":\"keyword\"},
    \"latency_ms\":{\"type\":\"integer\"},
    \"embedding\":{\"type\":\"knn_vector\",\"dimension\":${DIMS},
      \"method\":{\"name\":\"hnsw\",\"engine\":\"nmslib\",\"space_type\":\"cosinesimil\"}}
  }}
}"
echo

echo "[OS] Gerando ${DOCS} docs (via container python) e fazendo bulk..."
docker run --rm -i -e DOCS -e DIMS python:3.11 python - <<'PY' | \
  curl -fSk -u "${OS_USER}:${OS_PASS}" -H 'Content-Type: application/x-ndjson' \
    -XPOST "${OS_HOST}/logs/_bulk" --data-binary @- > /tmp/os_bulk_resp.json
import json, random, datetime, os, sys
DOCS=int(os.environ.get("DOCS","200000")); DIMS=int(os.environ.get("DIMS","128"))
services=["api-gateway","checkout","payment","auth","catalog"]
for i in range(DOCS):
    doc={"@timestamp":(datetime.datetime.utcnow()-datetime.timedelta(seconds=random.randint(0,172800))).isoformat()+"Z",
         "service":random.choice(services),"level":random.choice(["INFO","WARN","ERROR"]),
         "message":f"event {i}","req_id":f"id{i}","latency_ms":random.randint(1,2500),
         "embedding":[random.uniform(-1,1) for _ in range(DIMS)]}
    sys.stdout.write('{"index":{}}\n'); sys.stdout.write(json.dumps(doc)+'\n')
PY

if grep -q '"errors":\s*true' /tmp/os_bulk_resp.json; then
  echo "[OS] ERRO no bulk:"; head -n 60 /tmp/os_bulk_resp.json; exit 1
fi

curl -fSk -u "${OS_USER}:${OS_PASS}" "${OS_HOST}/_refresh" >/dev/null
echo "[OS] Count:"; curl -fSk -u "${OS_USER}:${OS_PASS}" "${OS_HOST}/logs/_count?pretty"
echo
