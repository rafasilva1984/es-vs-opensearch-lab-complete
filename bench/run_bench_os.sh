#!/usr/bin/env bash
set -euo pipefail

# ===== Config =====
OS_HOST="${OS_HOST:-https://127.0.0.1:9201}"
OS_USER="${OS_USER:-admin}"
OS_PASS="${OS_PASS:-Admin123!ChangeMe}"
INDEX="${INDEX:-logs}"
DIMS="${DIMS:-128}"
N="${N:-20}"
K="${K:-10}"
OUT_DIR="bench/results"
mkdir -p "$OUT_DIR"

echo "[OS] Benchmark contra $OS_HOST/$INDEX  (runs=$N, dims=$DIMS, k=$K)"

# ---- helpers ----
AUTH=(-u "$OS_USER:$OS_PASS" -k)  # TLS self-signed + Basic
rand_vec() {
  awk -v d="$DIMS" 'BEGIN{
    srand();
    printf("[");
    for(i=0;i<d;i++){v=((rand()*2)-1); printf("%s%.6f",(i?",":""),v);}
    printf("]");
  }'
}
percentiles() {
  awk '{x[NR]=$1; s+=$1} END{
    n=NR; if(n==0){print "0,0,0,0,0"; exit}
    asort(x);
    p50 = x[int((n+1)*0.50)];
    p95 = x[int((n+1)*0.95)];
    min=x[1]; max=x[n]; avg=s/n;
    printf("%.4f,%.4f,%.4f,%.4f,%.4f\n",avg,p50,p95,min,max);
  }'
}
measure() {  # $1=URL  $2=JSON body
  local url="$1" body="$2" t
  for i in $(seq 1 "$N"); do
    t=$(curl "${AUTH[@]}" -s -o /dev/null -w "%{time_total}" -H "Content-Type: application/json" --data "$body" "$url")
    echo "$t"
  done
}

# ---- queries ----
AGG_BODY='{
  "size": 0,
  "aggs": {
    "by_service": { "terms": { "field": "service", "size": 10 } },
    "latency": { "stats": { "field": "latency_ms" } }
  }
}'

VEC=$(rand_vec)
# OpenSearch k-NN nativo
KNN_BODY=$(cat <<JSON
{
  "size": $K,
  "query": {
    "knn": {
      "embedding": {
        "vector": $VEC,
        "k": $K
      }
    }
  }
}
JSON
)

echo "[OS] Agregação..."
AGG_TIMES=$(measure "$OS_HOST/$INDEX/_search" "$AGG_BODY")
AGG_METRICS=$(printf "%s\n" "$AGG_TIMES" | percentiles)

echo "[OS] kNN..."
KNN_TIMES=$(measure "$OS_HOST/$INDEX/_search" "$KNN_BODY")
KNN_METRICS=$(printf "%s\n" "$KNN_TIMES" | percentiles)

# salvar CSVs
printf "run,time_total\n" > "$OUT_DIR/os_agg_raw.csv"
printf "%s\n" "$AGG_TIMES" | nl -w1 -s, >> "$OUT_DIR/os_agg_raw.csv"

printf "run,time_total\n" > "$OUT_DIR/os_knn_raw.csv"
printf "%s\n" "$KNN_TIMES" | nl -w1 -s, >> "$OUT_DIR/os_knn_raw.csv"

printf "scenario,avg,p50,p95,min,max\nOS-agg,%s\nOS-knn,%s\n" "$AGG_METRICS" "$KNN_METRICS" > "$OUT_DIR/os_summary.csv"

# console
echo
echo "== OS Summary =="
column -s, -t "$OUT_DIR/os_summary.csv"
echo
echo "Arquivos:"
echo "  $OUT_DIR/os_summary.csv"
echo "  $OUT_DIR/os_agg_raw.csv"
echo "  $OUT_DIR/os_knn_raw.csv"
