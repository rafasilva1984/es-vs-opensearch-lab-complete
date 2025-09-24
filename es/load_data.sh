#!/usr/bin/env bash
set -euo pipefail

# ES no host (porta publicada pelo docker-compose)
ES_HOST="${ES_HOST:-http://host.docker.internal:9200}"
DOCS="${DOCS:-200000}"
DIMS="${DIMS:-128}"
BATCH_DOCS="${BATCH_DOCS:-5000}"   # 5k docs por lote ~ seguro pro limite 100MB

echo "[ES] Iniciando carga: ${DOCS} docs, ${DIMS}D, lote=${BATCH_DOCS}"

docker run --rm -e ES_HOST -e DOCS -e DIMS -e BATCH_DOCS python:3.11 bash -lc '
python - <<PY
import json, random, datetime, os, urllib.request, base64, ssl

ES_HOST=os.environ["ES_HOST"]
DOCS=int(os.getenv("DOCS","200000"))
DIMS=int(os.getenv("DIMS","128"))
BATCH=int(os.getenv("BATCH_DOCS","5000"))

ctx=ssl.create_default_context()
# ES aqui é HTTP; se alguém colocar HTTPS, aceitar cert self-signed:
ctx.check_hostname=False
ctx.verify_mode=ssl.CERT_NONE

def http(method, path, data=None, headers=None):
    if headers is None: headers={}
    if data is not None and not isinstance(data,(bytes,bytearray)):
        data = data.encode("utf-8")
    req=urllib.request.Request(ES_HOST+path, data=data, method=method, headers=headers)
    return urllib.request.urlopen(req, context=ctx).read()

def json_req(method, path, body):
    return http(method, path, json.dumps(body), {"Content-Type":"application/json"})

# DELETE índice (ignora 404)
try: http("DELETE","/logs"); except: pass

# PUT índice com mapping
json_req("PUT","/logs",{
  "mappings":{"properties":{
    "@timestamp":{"type":"date"},
    "service":{"type":"keyword"},
    "level":{"type":"keyword"},
    "message":{"type":"text"},
    "req_id":{"type":"keyword"},
    "latency_ms":{"type":"integer"},
    "embedding":{"type":"dense_vector","dims":DIMS}
}}})

services=["api-gateway","checkout","payment","auth","catalog"]

def bulk(batch_docs):
    # monta NDJSON
    lines=[]
    for d in batch_docs:
        lines.append("{\"index\":{}}")
        lines.append(json.dumps(d))
    body="\n".join(lines)+"\n"
    resp=http("POST","/logs/_bulk", body, {"Content-Type":"application/x-ndjson"})
    j=json.loads(resp.decode("utf-8"))
    if j.get("errors"):
        # imprime 1º erro e aborta
        for it in j.get("items",[]):
            if "error" in it.get("index",{}):
                raise SystemExit(f"Bulk error: {it['index']['error']}")
        raise SystemExit("Bulk errors:true (sem detalhes)")
    return j

buf=[]
sent=0
for i in range(DOCS):
    doc={
      "@timestamp":(datetime.datetime.utcnow()-datetime.timedelta(seconds=random.randint(0,172800))).isoformat()+"Z",
      "service":random.choice(services),
      "level":random.choice(["INFO","WARN","ERROR"]),
      "message":f"event {i}",
      "req_id":f"id{i}",
      "latency_ms":random.randint(1,2500),
      "embedding":[random.uniform(-1,1) for _ in range(DIMS)]
    }
    buf.append(doc)
    if len(buf)==BATCH:
        bulk(buf); sent+=len(buf); buf=[]
        print(f"[ES] bulk enviado, total={sent}/{DOCS}", flush=True)
if buf:
    bulk(buf); sent+=len(buf)
    print(f"[ES] bulk enviado, total={sent}/{DOCS}", flush=True)

# count
c=http("GET","/logs/_count", None, {"Accept":"application/json"})
print("[ES] Count:", c.decode("utf-8"))
PY
'
