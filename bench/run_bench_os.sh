#!/usr/bin/env bash
set -euo pipefail
OS_HOST="${OS_HOST:-http://localhost:${OS_HTTP:-9201}}"

echo "[OS] Agregação (avg latency por serviço)..."
/usr/bin/time -f "elapsed=%E user=%U sys=%S" curl -s -H 'Content-Type: application/json' "${OS_HOST}/logs/_search" -d '{
  "size": 0,
  "aggs": {"per_service": {"terms": {"field": "service"},
    "aggs": {"lat":{"avg":{"field":"latency_ms"}}}}}
}' > /dev/null

echo "[OS] kNN (vector search)..."
python3 - <<'PY' | curl -s -H 'Content-Type: application/json' "${OS_HOST}/logs/_search" -d @- > /dev/null
import json, random
v=[random.uniform(-1,1) for _ in range(128)]
print(json.dumps({"size":10,"query":{"knn":{"embedding":{"vector":v,"k":10}}},
"_source":["service","latency_ms"]}))
PY
echo "[OS] OK"
