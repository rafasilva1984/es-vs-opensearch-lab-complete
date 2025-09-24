#!/usr/bin/env bash
set -euo pipefail

ES_HOST="${ES_HOST:-http://127.0.0.1:9200}"
DOCS="${DOCS:-200000}"
DIMS="${DIMS:-128}"
BATCH_DOCS="${BATCH_DOCS:-5000}"   # docs por lote (cada doc = 2 linhas NDJSON)

workdir="$(mktemp -d)"
outdir="${workdir}/out"
mkdir -p "${outdir}"

# Apaga índice anterior (silencioso se 404)
curl -sS -XDELETE "${ES_HOST}/logs" -o /dev/null || true

echo "[ES] Criando índice 'logs' (${DIMS}D dense_vector)..."
curl -fsS -XPUT "${ES_HOST}/logs" -H 'Content-Type: application/json' -d "{
  \"mappings\": { \"properties\": {
    \"@timestamp\":{\"type\":\"date\"},
    \"service\":{\"type\":\"keyword\"},
    \"level\":{\"type\":\"keyword\"},
    \"message\":{\"type\":\"text\"},
    \"req_id\":{\"type\":\"keyword\"},
    \"latency_ms\":{\"type\":\"integer\"},
    \"embedding\":{\"type\":\"dense_vector\",\"dims\":${DIMS}}
  }} }" > /dev/null
echo "[ES] OK."

echo "[ES] Gerando ${DOCS} docs em lotes de ${BATCH_DOCS} (via contêiner python) ..."
docker run --rm -e DOCS -e DIMS -e BATCH_DOCS \
  -v "${outdir}:/out" python:3.11 python - <<'PY'
import json, random, datetime, os
DOCS=int(os.environ.get("DOCS","200000"))
DIMS=int(os.environ.get("DIMS","128"))
BATCH=int(os.environ.get("BATCH_DOCS","5000"))
services=["api-gateway","checkout","payment","auth","catalog"]
out="/out"
batch_id=0
def emit(path, docs):
    with open(path,"w") as f:
        for d in docs:
            f.write('{"index":{}}\n')
            f.write(json.dumps(d)+"\n")
buf=[]
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
    buf.append(doc)
    if len(buf)==BATCH:
        p=os.path.join(out, f"part_{batch_id:05d}.ndjson")
        emit(p, buf); buf=[]; batch_id+=1
if buf:
    p=os.path.join(out, f"part_{batch_id:05d}.ndjson")
    emit(p, buf)
PY

echo "[ES] Enviando lotes para _bulk ..."
shopt -s nullglob
parts=( "${outdir}"/part_*.ndjson )
if [ ${#parts[@]} -eq 0 ]; then
  echo "[ES] ERRO: nenhum lote gerado."; exit 1
fi

for part in "${parts[@]}"; do
  printf "  -> %s ... " "$(basename "$part")"
  curl -fsS -H 'Content-Type: application/x-ndjson' -XPOST "${ES_HOST}/logs/_bulk" --data-binary @"${part}" > "${part}.resp"
  if grep -q '"errors":\s*true' "${part}.resp"; then
    echo "ERRO"; head -n 60 "${part}.resp"; exit 1
  else
    echo "ok"
  fi
done

curl -fsS "${ES_HOST}/_refresh" > /dev/null
echo "[ES] Count:"; curl -fsS "${ES_HOST}/logs/_count?pretty"
rm -rf "${workdir}"
echo
