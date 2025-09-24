#!/usr/bin/env bash
set -euo pipefail

# OS publicado no host com TLS e Basic Auth
OS_HOST="${OS_HOST:-https://host.docker.internal:9201}"
OS_USER="${OS_USER:-admin}"
OS_PASS="${OS_PASS:-Admin123!ChangeMe}"
DOCS="${DOCS:-200000}"
DIMS="${DIMS:-128}"
BATCH_DOCS="${BATCH_DOCS:-5000}"

echo "[OS] Iniciando carga: ${DOCS} docs, ${DIMS}D, lote=${BATCH_DOCS}"

docker run --rm -e OS_HOST -e OS_USER -e OS_PASS -e DOCS -e DIMS -e BATCH_DOCS python:3.11 bash -lc '
python - <<PY
import json, random, datetime, os, urllib.request, ssl, base64

OS_HOST=os.environ["OS_HOST"]
USER=os.environ["OS_USER"]; PASS=os.environ["OS_PASS"]
DOCS=int(os.getenv("DOCS","200000"))
DIMS=int(os.getenv("DIMS","128"))
BATCH=int(os.getenv("BATCH_DOCS","5000"))

# TLS: aceitar self-signed (LAB)
ctx=ssl.create_default_context()
ctx.check_hostname=False
ctx.verify_mode=ssl.CERT_NONE

basic = base64.b64encode(f"{USER}:{PASS}".encode()).decode()
auth_hdr = {"Authorization": f"Basic {basic}"}

def http(method, path, data=None, headers=None):
    hs={"Accept":"application/json"}
    if headers: hs.update(headers)
    hs.update(auth_hdr)
    if data is not None and not isinstance(data,(bytes,bytearray)):
        data = data.encode("utf-8")
    req=urllib.request.Request(OS_HOST+path, data=data, method=method, headers=hs)
    return urllib.request.urlopen(req, context=ctx).read()

def json_req(method, path, body):
    return http(method, path, json.dumps(body), {"Content-Type":"application/json"})

# DELETE índice (ignora 404)
try: http("DELETE","/logs"); except: pass

# PUT índice com knn_vector
json_req("PUT","/logs",{
  "settings":{"index.knn": True},
  "mappings":{"properties":{
    "@timestamp":{"type":"date"},
    "service":{"type":"keyword"},
    "level":{"type":"keyword"},
    "message":{"type":"text"},
    "req_id":{"type":"keyword"},
    "latency_ms":{"type":"integer"},
    "embedding":{"type":"knn_vector","dimension":DIMS,
                 "method":{"name":"hnsw","engine":"nmslib","space_type":"cosinesimil"}}
}})

services=["api-gateway","checkout","payment","auth","catalog"]

def bulk(batch_docs):
    lines=[]
    for d in batch_docs:
        lines.append("{\"index\":{}}")
        lines.append(json.dumps(d))
    body="\n".join(lines)+"\n"
    resp=http("POST","/logs/_bulk", body, {"Content-Type":"application/x-ndjson"})
    j=json.loads(resp.decode("utf-8"))
    if j.get("errors"):
        for it in j.get("items",[]):
            if "error" in it.get("index",{}):
                raise SystemExit(f"Bulk error: {it['index']['error']}")
        raise SystemExit("Bulk errors:true (sem detalhes)")
    return j

buf=[]; sent=0
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
        print(f"[OS] bulk enviado, total={sent}/{DOCS}", flush=True)
if buf:
    bulk(buf); sent+=len(buf)
    print(f"[OS] bulk enviado, total={sent}/{DOCS}", flush=True)

c=http("GET","/logs/_count")
print("[OS] Count:", c.decode("utf-8"))
PY
'
