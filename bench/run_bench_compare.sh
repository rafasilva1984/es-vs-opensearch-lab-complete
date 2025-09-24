#!/usr/bin/env bash
# v2: self-contained + logs + arquivos sempre gerados
set -euo pipefail

# ===== Config =====
ES_HOST="${ES_HOST:-http://127.0.0.1:9200}"
OS_HOST="${OS_HOST:-https://127.0.0.1:9201}"
OS_USER="${OS_USER:-admin}"
OS_PASS="${OS_PASS:-Admin123!ChangeMe}"
INDEX="${INDEX:-logs}"
DIMS="${DIMS:-128}"
K="${K:-10}"
N="${N:-30}"              # repetições
OUT_DIR="bench/results"
mkdir -p "$OUT_DIR"

# ===== Aparência =====
log(){ printf "[%s] %s\n" "$(date +%H:%M:%S)" "$*"; }

# ===== Helpers numéricos =====
percentiles() { # stdin: um valor por linha -> avg,p50,p95,min,max
  awk '{x[NR]=$1; s+=$1} END{
    n=NR; if(n==0){print "0,0,0,0,0"; exit}
    asort(x);
    p50=x[int((n+1)*0.50)]; p95=x[int((n+1)*0.95)];
    min=x[1]; max=x[n]; avg=s/n;
    printf "%.4f,%.4f,%.4f,%.4f,%.4f\n",avg,p50,p95,min,max;
  }'
}
pct_gain(){ awk -v a="$1" -v b="$2" 'BEGIN{if(a==0||b==0){print "NA"} else printf("%.1f%%",(1-b/a)*100)}'; }
spdup(){ awk -v a="$1" -v b="$2" 'BEGIN{if(a==0||b==0){print "NA"} else printf("%.2fx",a/b)}'; }

# ===== Vetor aleatório =====
rand_vec() {
  awk -v d="$DIMS" 'BEGIN{srand(); printf("["); for(i=0;i<d;i++){v=((rand()*2)-1); printf("%s%.6f",(i?",":""),v)} printf("]")}'
}

# ===== Medição com curl =====
measure_es(){ # $1=json body
  local body="$1" t; for i in $(seq 1 "$N"); do
    t=$(curl -s -o /dev/null -w "%{time_total}" -H "Content-Type: application/json" --data "$body" "$ES_HOST/$INDEX/_search")
    echo "$t"
  done
}
measure_os(){ # $1=json body
  local body="$1" t; for i in $(seq 1 "$N"); do
    t=$(curl -s -k -u "$OS_USER:$OS_PASS" -o /dev/null -w "%{time_total}" -H "Content-Type: application/json" --data "$body" "$OS_HOST/$INDEX/_search")
    echo "$t"
  done
}

# ===== Query bodies =====
AGG_BODY='{
  "size": 0,
  "aggs": {
    "by_service": { "terms": { "field": "service", "size": 10 } },
    "latency": { "stats": { "field": "latency_ms" } }
  }
}'
VEC="$(rand_vec)"
ES_KNN_BODY=$(cat <<JSON
{
  "size": $K,
  "query": {
    "script_score": {
      "query": { "match_all": {} },
      "script": {
        "source": "cosineSimilarity(params.q, 'embedding') + 1.0",
        "params": { "q": $VEC }
      }
    }
  }
}
JSON
)
OS_KNN_BODY=$(cat <<JSON
{
  "size": $K,
  "query": {
    "knn": {
      "embedding": { "vector": $VEC, "k": $K }
    }
  }
}
JSON
)

log "Bench combinado (runs=$N, k=$K, dims=$DIMS)"
log "ES: $ES_HOST/$INDEX"
log "OS: $OS_HOST/$INDEX"

# ===== Rodar testes =====
log "ES - Agregação..."
ES_AGG_TIMES=$(measure_es "$AGG_BODY");   ES_AGG_METRICS=$(printf "%s\n" "$ES_AGG_TIMES" | percentiles)
log "ES - kNN (script_score/cosineSimilarity)..."
ES_KNN_TIMES=$(measure_es "$ES_KNN_BODY"); ES_KNN_METRICS=$(printf "%s\n" "$ES_KNN_TIMES" | percentiles)

log "OS - Agregação..."
OS_AGG_TIMES=$(measure_os "$AGG_BODY");   OS_AGG_METRICS=$(printf "%s\n" "$OS_AGG_TIMES" | percentiles)
log "OS - kNN (ANN/HNSW)..."
OS_KNN_TIMES=$(measure_os "$OS_KNN_BODY"); OS_KNN_METRICS=$(printf "%s\n" "$OS_KNN_TIMES" | percentiles)

# ===== Salvar CSVs brutos =====
printf "run,time_total\n" > "$OUT_DIR/es_agg_raw.csv";  printf "%s\n" "$ES_AGG_TIMES" | nl -w1 -s, >> "$OUT_DIR/es_agg_raw.csv"
printf "run,time_total\n" > "$OUT_DIR/es_knn_raw.csv";  printf "%s\n" "$ES_KNN_TIMES" | nl -w1 -s, >> "$OUT_DIR/es_knn_raw.csv"
printf "run,time_total\n" > "$OUT_DIR/os_agg_raw.csv";  printf "%s\n" "$OS_AGG_TIMES" | nl -w1 -s, >> "$OUT_DIR/os_agg_raw.csv"
printf "run,time_total\n" > "$OUT_DIR/os_knn_raw.csv";  printf "%s\n" "$OS_KNN_TIMES" | nl -w1 -s, >> "$OUT_DIR/os_knn_raw.csv"

# ===== Summaries por engine =====
printf "scenario,avg,p50,p95,min,max\nES-agg,%s\nES-knn,%s\n" "$ES_AGG_METRICS" "$ES_KNN_METRICS" > "$OUT_DIR/es_summary.csv"
printf "scenario,avg,p50,p95,min,max\nOS-agg,%s\nOS-knn,%s\n" "$OS_AGG_METRICS" "$OS_KNN_METRICS" > "$OUT_DIR/os_summary.csv"

# ===== CSV combinado =====
COMB="$OUT_DIR/combined_summary.csv"
{
  echo "engine,scenario,avg,p50,p95,min,max"
  echo "ES,agg,$ES_AGG_METRICS"
  echo "ES,knn,$ES_KNN_METRICS"
  echo "OS,agg,$OS_AGG_METRICS"
  echo "OS,knn,$OS_KNN_METRICS"
} > "$COMB"

# ===== Comparação / Análise =====
ES_AGG_AVG=$(echo "$ES_AGG_METRICS" | cut -d, -f1)
ES_KNN_AVG=$(echo "$ES_KNN_METRICS" | cut -d, -f1)
OS_AGG_AVG=$(echo "$OS_AGG_METRICS" | cut -d, -f1)
OS_KNN_AVG=$(echo "$OS_KNN_METRICS" | cut -d, -f1)

WIN_AGG=$(awk -v es="$ES_AGG_AVG" -v os="$OS_AGG_AVG" 'BEGIN{print (es<os)?"ES":"OS"}')
WIN_KNN=$(awk -v es="$ES_KNN_AVG" -v os="$OS_KNN_AVG" 'BEGIN{print (es<os)?"ES":"OS"}')

AGG_GAIN=$(pct_gain "$ES_AGG_AVG" "$OS_AGG_AVG")
KNN_GAIN=$(pct_gain "$ES_KNN_AVG" "$OS_KNN_AVG")
SPD_AGG=$(spdup "$ES_AGG_AVG" "$OS_AGG_AVG")
SPD_KNN=$(spdup "$ES_KNN_AVG" "$OS_KNN_AVG")

# ===== Relatório Markdown =====
REPORT="$OUT_DIR/report.md"
{
  echo "# Benchmark ES vs OpenSearch — $(date +'%Y-%m-%d %H:%M:%S')"
  echo
  echo "## Parâmetros"
  echo "- Runs: **$N**"
  echo "- Top-K: **$K**"
  echo "- Dimensões: **$DIMS**"
  echo "- Índice: **$INDEX**"
  echo
  echo "## Resultados (média de latência em segundos)"
  echo
  echo "| Engine | Cenário | avg | p50 | p95 | min | max |"
  echo "|-------:|:-------|----:|----:|----:|----:|----:|"
  awk -F, 'NR>1{printf("| %s | %s | %.4f | %.4f | %.4f | %.4f | %.4f |\n",$1,$2,$3,$4,$5,$6,$7)}' "$COMB"
  echo
  echo "## Quem venceu?"
  echo "- **Agregação:** $WIN_AGG  (ganho vs outro: $AGG_GAIN; speedup ES/OS=$SPD_AGG)"
  echo "- **kNN:** $WIN_KNN  (ganho vs outro: $KNN_GAIN; speedup ES/OS=$SPD_KNN)"
  echo
  echo "## Explicação rápida"
  echo "- **kNN**: OpenSearch usa \`knn_vector\` com ANN/HNSW (aproximação por grafo). Isso evita varredura completa e escala melhor conforme o volume cresce."
  echo "- **ES kNN (neste lab)**: \`dense_vector\` + \`script_score\` (cosineSimilarity) = busca exata; em coleções pequenas pode empatar, mas tende a ficar mais lenta em bases grandes."
  echo "- **Agregações**: ambos usam estruturas invertidas; diferenças normalmente vêm de cache quente, shards/replicas e I/O."
  echo
  echo "## Próximos passos"
  echo "1) Aumente DOCS para 100k+ e repita."
  echo "2) Faça warmup (rodar 1x antes de medir)."
  echo "3) Padronize: 1 shard, 0 replicas, e \`refresh_interval: -1\` na ingestão."
} > "$REPORT"

# ===== Console =====
echo
log "== Summary combinado (avg em s) =="
column -s, -t "$COMB" || cat "$COMB"   # fallback caso 'column' não exista
echo
log "Agregação: vencedor=$WIN_AGG | ES avg=$ES_AGG_AVG  OS avg=$OS_AGG_AVG | speedup ES/OS=$SPD_AGG | ganho=$AGG_GAIN"
log "kNN:        vencedor=$WIN_KNN | ES avg=$ES_KNN_AVG  OS avg=$OS_KNN_AVG | speedup ES/OS=$SPD_KNN | ganho=$KNN_GAIN"
echo
log "Relatório: $REPORT"
log "CSVs:      $COMB"
