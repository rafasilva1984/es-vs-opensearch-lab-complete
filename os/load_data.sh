#!/usr/bin/env bash
set -euo pipefail

OS_HOST="${OS_HOST:-https://127.0.0.1:9201}"
OS_USER="${OS_USER:-admin}"
OS_PASS="${OS_PASS:-Admin123!ChangeMe}"
DOCS="${DOCS:-200000}"
DIMS="${DIMS:-128}"
BATCH_DOCS="${BATCH_DOCS:-5000}"

workdir="$(mktemp -d)"
outdir="${workdir}/out"
mkdir -p "${outdir}"

# Apaga índice anterior (silencioso se 404)
curl -sS -k -u "${OS_USER}:${OS_PASS}" -XDELETE "${OS_HOST}/logs" -o /dev/null || true

echo "[OS] Criando índice 'logs' (${DIMS}D knn_vector) ..."
curl -fsS -k -u "${OS_USER}:${OS_PASS}" -XPUT "${OS_HOST}/logs" -H 'Content-Type: application/json' -d "{
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
echo "[OS] OK."

echo "[OS] Gerando ${DOCS} docs em lotes de ${BATCH_DOCS} (via contêiner python) ..."
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

echo "[OS] Enviando lotes para _bulk ..."
shopt -s nullglob
parts=( "${outdir}"/part_*.ndjson )
if [ ${#parts[@]} -eq 0 ]; then
  echo "[OS] ERRO: nenhum lote gerado."; exit 1
fi

for part in "${parts[@]}"; do
  printf "  -> %s ... " "$(basename "$part")"
  curl -fsS -k -u "${OS_USER}:${OS_PASS}" -H 'Content-Type: application/x-ndjson' \
       -XPOST "${OS_HOST}/logs/_bulk" --data-binary @"${part}" > "${part}.resp"
  if grep -q '"errors":\s*true' "${part}.resp"; then
    echo "ERRO"; head -n 60 "${part}.resp"; exit 1
  else
    echo "ok"
  fi
done

curl -fsS -k -u "${OS_USER}:${OS_PASS}" "${OS_HOST}/_refresh" > /dev/null
echo "[OS] Count:"; curl -fsS -k -u "${OS_USER}:${OS_PASS}" "${OS_HOST}/logs/_count?pretty"
rm -rf "${workdir}"
echo
