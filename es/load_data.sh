#!/usr/bin/env bash
set -euo pipefail

# === CONFIG FIXA ===
ES_HOST="http://host.docker.internal:9200"
DOCS=500000
DIMS=128
BATCH=50000

echo "[ES] Iniciando carga: ${DOCS} docs, ${DIMS}D, lote=${BATCH}"

docker run --rm python:3.11 bash -lc "
python - <<PY
import json, random, datetime, urllib.request, ssl

ES_HOST='${ES_HOST}'
DOCS=${DOCS}
DIMS=${DIMS}
BATCH=${BATCH}

ctx=ssl.create_default_context()
ctx.check_hostname=False
ctx.verify_mode=ssl.CERT_NONE

def http(method, path, data=None, headers=None):
    if headers is None: headers={}
    if data is not None and not isinstance(data,(bytes,bytearray)):
        data = data.encode('utf-8')
    req=urllib.request.Request(ES_HOST+path, data=data, method=method, headers=headers)
    return urllib.request.urlopen(req, context=ctx).read()

def json_req(method, path, body):
    return http(method, path, json.dumps(body), {'Content-Type':'application/json'})

# DELETE índice (ignora se não existe)
try: http('DELETE','/logs')
except: pass

# PUT índice
json_req('PUT','/logs',{
  'mappings':{'properties':{
    '@timestamp':{'type':'date'},
    'service':{'type':'keyword'},
    'level':{'type':'keyword'},
    'message':{'type':'text'},
    'req_id':{'type':'keyword'},
    'latency_ms':{'type':'integer'},
    'embedding':{'type':'dense_vector','dims':DIMS}
  }}
})

services=['api-gateway','checkout','payment','auth','catalog']

def bulk(batch_docs):
    lines=[]
    for d in batch_docs:
        lines.append('{\"index\":{}}')
        lines.append(json.dumps(d))
    body='\\n'.join(lines)+'\\n'
    resp=http('POST','/logs/_bulk', body, {'Content-Type':'application/x-ndjson'})
    j=json.loads(resp.decode('utf-8'))
    if j.get('errors'):
        raise SystemExit('Bulk errors:true')
    return j

buf=[]; sent=0
for i in range(DOCS):
    doc={
      '@timestamp':(datetime.datetime.utcnow()-datetime.timedelta(seconds=random.randint(0,172800))).isoformat()+'Z',
      'service':random.choice(services),
      'level':random.choice(['INFO','WARN','ERROR']),
      'message':f'event {i}',
      'req_id':f'id{i}',
      'latency_ms':random.randint(1,2500),
      'embedding':[random.uniform(-1,1) for _ in range(DIMS)]
    }
    buf.append(doc)
    if len(buf)==BATCH:
        bulk(buf); sent+=len(buf); buf=[]
        print(f'[ES] bulk enviado, total={sent}/{DOCS}', flush=True)
if buf:
    bulk(buf); sent+=len(buf)
    print(f'[ES] bulk enviado, total={sent}/{DOCS}', flush=True)

c=http('GET','/logs/_count', None, {'Accept':'application/json'})
print('[ES] Count:', c.decode('utf-8'))
PY
"
