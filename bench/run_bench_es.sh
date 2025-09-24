#!/usr/bin/env bash
set -euo pipefail
ES_HOST="${ES_HOST:-http://localhost:${ES_HTTP:-9200}}"

echo "[ES] Agregação (avg latency por serviço)..."
/usr/bin/time -f "elapsed=%E user=%U sys=%S" curl -s -H 'Content-Type: application/json' "${ES_HOST}/logs/_search" -d '{
  "size": 0,
  "aggs": {"per_service": {"terms": {"field": "service"},
    "aggs": {"lat":{"avg":{"field":"latency_ms"}}}}}
}' > /dev/null

echo "[ES] kNN (vector search)..."
python3 - <<'PY' | curl -s -H 'Content-Type: application/json' "${ES_HOST}/logs/_search" -d @- > /dev/null
import json, random
v=[random.uniform(-1,1) for _ in range(128)]
print(json.dumps({"knn":{"field":"embedding","query_vector":v,"k":10,"num_candidates":200},
"_source":["service","latency_ms"]}))
PY
echo "[ES] OK"
