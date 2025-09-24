#!/usr/bin/env bash
set -euo pipefail

OS_HOST="${OS_HOST:-https://127.0.0.1:9201}"
OS_USER="${OS_USER:-admin}"
OS_PASS="${OS_PASS:-Admin123!ChangeMe}"
DOCS="${DOCS:-200000}"
DIMS="${DIMS:-128}"
CHUNK_SIZE_MB="${CHUNK_SIZE_MB:-40}"

workdir="$(mktemp -d)"
ndjson="${workdir}/os_bulk.ndjson"

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
}" >/dev/null
echo "[OS] OK."

echo "[OS] Gerando ${DOCS} docs (via container python) em NDJSON..."
docker run --rm -e DOCS -e DIMS python:3.11 python - <<'PY' > "${ndjson}"
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

echo "[OS] Split em partes de ~${CHUNK_SIZE_MB}MB e fazendo _bulk..."
split -b "${CHUNK_SIZE_MB}m" -d -a 4 "${ndjson}" "${workdir}/part_"

for part in "${workdir}"/part_*; do
  printf "[OS] Enviando %s ... " "$(basename "$part")"
  curl -fSk -u "${OS_USER}:${OS_PASS}" -H 'Content-Type: application/x-ndjson' \
       -XPOST "${OS_HOST}/logs/_bulk" --data-binary @"${part}" > "${part}.resp"
  if grep -q '"errors":\s*true' "${part}.resp"; then
    echo "ERRO"; head -n 60 "${part}.resp"; rm -rf "${workdir}"; exit 1
  else
    echo "ok"
  fi
done

curl -fSk -u "${OS_USER}:${OS_PASS}" "${OS_HOST}/_refresh" >/dev/null
echo "[OS] Count:"; curl -fSk -u "${OS_USER}:${OS_PASS}" "${OS_HOST}/logs/_count?pretty"
rm -rf "${workdir}"
echo
