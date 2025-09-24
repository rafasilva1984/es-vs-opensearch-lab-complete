#!/usr/bin/env bash
set -euo pipefail

ES_HOST="${ES_HOST:-http://127.0.0.1:9200}"
DOCS="${DOCS:-200000}"
DIMS="${DIMS:-128}"
CHUNK_SIZE_MB="${CHUNK_SIZE_MB:-40}"  # cada parte ~40MB, ficar bem abaixo do default 100MB

workdir="$(mktemp -d)"
ndjson="${workdir}/es_bulk.ndjson"

# apaga índice antigo (ignora 404)
curl -fsS -XDELETE "${ES_HOST}/logs" >/dev/null || true

echo "[ES] Criando índice 'logs' (${DIMS}D dense_vector)..."
curl -fS -XPUT "${ES_HOST}/logs" -H 'Content-Type: application/json' -d "{
  \"mappings\": { \"properties\": {
    \"@timestamp\":{\"type\":\"date\"},
    \"service\":{\"type\":\"keyword\"},
    \"level\":{\"type\":\"keyword\"},
    \"message\":{\"type\":\"text\"},
    \"req_id\":{\"type\":\"keyword\"},
    \"latency_ms\":{\"type\":\"integer\"},
    \"embedding\":{\"type\":\"dense_vector\",\"dims\":${DIMS}}
  }} }" >/dev/null
echo "[ES] OK."

echo "[ES] Gerando ${DOCS} docs (via container python) em NDJSON..."
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

echo "[ES] Split em partes de ~${CHUNK_SIZE_MB}MB e fazendo _bulk..."
split -b "${CHUNK_SIZE_MB}m" -d -a 4 "${ndjson}" "${workdir}/part_"

for part in "${workdir}"/part_*; do
  printf "[ES] Enviando %s ... " "$(basename "$part")"
  curl -fS -H 'Content-Type: application/x-ndjson' -XPOST "${ES_HOST}/logs/_bulk" --data-binary @"${part}" > "${part}.resp"
  if grep -q '"errors":\s*true' "${part}.resp"; then
    echo "ERRO"; head -n 60 "${part}.resp"; rm -rf "${workdir}"; exit 1
  else
    echo "ok"
  fi
done

curl -fsS "${ES_HOST}/_refresh" >/dev/null
echo "[ES] Count:"; curl -fsS "${ES_HOST}/logs/_count?pretty"
rm -rf "${workdir}"
echo
