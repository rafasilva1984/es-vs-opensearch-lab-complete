#!/usr/bin/env bash
set -euo pipefail

OS_HOST="${OS_HOST:-https://127.0.0.1:9201}"
OS_USER="${OS_USER:-admin}"
OS_PASS="${OS_PASS:-Admin123!ChangeMe}"
DOCS="${DOCS:-200000}"
DIMS="${DIMS:-128}"

echo "[OS] Criando índice 'logs' com knn_vector (${DIMS}D) em ${OS_HOST} ..."
curl -k -u "${OS_USER}:${OS_PASS}" -s "${OS_HOST}/logs" -H 'Content-Type: application/json' -d "{
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
}" > /dev/null

echo "[OS] Gerando ${DOCS} docs (via container python) e fazendo bulk..."
docker run --rm -i -e DOCS -e DIMS python:3.11 python - <<'PY' | \
  curl -k -u "${OS_USER}:${OS_PASS}" -s -H 'Content-Type: application/x-ndjson' \
    -XPOST "${OS_HOST}/logs/_bulk" --data-binary @- > /dev/null
import json, random, datetime, os, sys
DOCS=int(os.environ.get("DOCS","200000"))
DIMS=int(os.environ.get("DIMS","128"))
services=["api-gateway","checkout","payment","auth","catalog"]
actions=[f"a{i}" for i in range(1,201)]
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
    sys.stdout.write(json.dumps({"index":{}})+"\n")
    sys.stdout.write(json.dumps(doc)+"\n")
PY
curl -k -u "${OS_USER}:${OS_PASS}" -s "${OS_HOST}/_refresh" > /dev/null
echo "[OS] Concluído."
