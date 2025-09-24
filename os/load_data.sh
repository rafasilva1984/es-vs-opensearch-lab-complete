#!/usr/bin/env bash
set -euo pipefail

# === CONFIG FIXA (edite aqui se quiser) ===
OS_HOST="https://host.docker.internal:9201"
OS_USER="admin"
OS_PASS="Admin123!ChangeMe"
DOCS=100000
DIMS=128
BATCH=10000

echo "[OS] Iniciando carga: ${DOCS} docs, ${DIMS}D, lote=${BATCH}"

docker run --rm python:3.11 bash -lc "
python - <<PY
import json, random, datetime, urllib.request, ssl, base64, urllib.error, sys

OS_HOST='${OS_HOST}'
USER='${OS_USER}'
PASS='${OS_PASS}'
DOCS=${DOCS}
DIMS=${DIMS}
BATCH=${BATCH}

# TLS: aceitar cert self-signed (LAB)
ctx=ssl.create_default_context()
ctx.check_hostname=False
ctx.verify_mode=ssl.CERT_NONE

basic = base64.b64encode(f\"{USER}:{PASS}\".encode()).decode()
AUTH = {'Authorization': f'Basic {basic}'}

def call(method, path, data=None, headers=None):
    hs={'Accept':'application/json'}
    hs.update(AUTH)
    if headers: hs.update(headers)
    if data is not None and not isinstance(data,(bytes,bytearray)):
        data=data.encode('utf-8')
    req=urllib.request.Request(OS_HOST+path, data=data, method=method, headers=hs)
    try:
        with urllib.request.urlopen(req, context=ctx) as r:
            return r.read()
    except urllib.error.HTTPError as e:
        body=e.read().decode('utf-8', 'ignore')
        print(f\"[OS][HTTP {e.code}] {method} {path}\\n{body}\", file=sys.stderr)
        raise

def jput(path, body):
    return call('PUT', path, json.dumps(body), {'Content-Type':'application/json'})

# DELETE índice (ignora 404)
try:
    call('DELETE','/logs')
except Exception:
    pass

# PUT índice (simples: só dimension; engine/method default -> lucene/hnsw)
jput('/logs', {
  'settings': {'index.knn': True},
  'mappings': {'properties': {
    '@timestamp': {'type':'date'},
    'service':    {'type':'keyword'},
    'level':      {'type':'keyword'},
    'message':    {'type':'text'},
    'req_id':     {'type':'keyword'},
    'latency_ms': {'type':'integer'},
    'embedding':  {'type':'knn_vector','dimension': DIMS}
  }}
})

services=['api-gateway','checkout','payment','auth','catalog']

def bulk_send(batch_docs):
    lines=[]
    for d in batch_docs:
        lines.append('{\"index\":{}}')
        lines.append(json.dumps(d))
    body='\\n'.join(lines)+'\\n'
    resp = call('POST','/logs/_bulk', body, {'Content-Type':'application/x-ndjson'})
    j=json.loads(resp.decode('utf-8'))
    if j.get('errors'):
        # mostra 1º erro
        for it in j.get('items',[]):
            err=it.get('index',{}).get('error')
            if err:
                raise SystemExit(f\"Bulk error: {err}\")
        raise SystemExit('Bulk errors:true')
    return j

buf=[]; sent=0
for i in range(DOCS):
    doc={
      '@timestamp': (datetime.datetime.utcnow()-datetime.timedelta(seconds=random.randint(0,172800))).isoformat()+'Z',
      'service':    random.choice(services),
      'level':      random.choice(['INFO','WARN','ERROR']),
      'message':    f'event {i}',
      'req_id':     f'id{i}',
      'latency_ms': random.randint(1,2500),
      'embedding':  [random.uniform(-1,1) for _ in range(DIMS)]
    }
    buf.append(doc)
    if len(buf)==BATCH:
        bulk_send(buf); sent+=len(buf); buf=[]
        print(f'[OS] bulk enviado, total={sent}/{DOCS}', flush=True)

if buf:
    bulk_send(buf); sent+=len(buf)
    print(f'[OS] bulk enviado, total={sent}/{DOCS}', flush=True)

count = call('GET','/logs/_count')
print('[OS] Count:', count.decode('utf-8'))
PY
"
