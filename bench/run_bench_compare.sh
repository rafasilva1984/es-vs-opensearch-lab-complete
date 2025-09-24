#!/usr/bin/env bash
set -euo pipefail

# ========= Config =========
ES_HOST="${ES_HOST:-http://127.0.0.1:9200}"
OS_HOST="${OS_HOST:-https://127.0.0.1:9201}"
OS_USER="${OS_USER:-admin}"
OS_PASS="${OS_PASS:-Admin123!ChangeMe}"
INDEX="${INDEX:-logs}"
DIMS="${DIMS:-128}"
K="${K:-10}"
N="${N:-30}"              # repetições por cenário
OUT_DIR="bench/results"
mkdir -p "$OUT_DIR"

# ========= Cores (se disponível) =========
if command -v tput >/dev/null 2>&1; then
  BOLD=$(tput bold); DIM=$(tput dim); RED=$(tput setaf 1); GRN=$(tput setaf 2)
  YLW=$(tput setaf 3); BLU=$(tput setaf 4); MAG=$(tput setaf 5); CYA=$(tput setaf 6); RST=$(tput sgr0)
else BOLD=""; DIM=""; RED=""; GRN=""; YLW=""; BLU=""; MAG=""; CYA=""; RST=""; fi

echo "${BOLD}► Bench combinado (runs=$N, k=$K, dims=$DIMS)${RST}"
echo "   ES: $ES_HOST/$INDEX"
echo "   OS: $OS_HOST/$INDEX"

# ========= 1) Rodar benches (reutilizando teus scripts) =========
N="$N" K="$K" DIMS="$DIMS" bench/run_bench_es.sh >/dev/null
N="$N" K="$K" DIMS="$DIMS" bench/run_bench_os.sh >/dev/null

# ========= 2) Ler summaries =========
# CSV: scenario,avg,p50,p95,min,max
read_csv() {
  local f="$1" scen="$2"
  awk -F, -v s="$scen" 'NR>1 && $1==s {print $0}' "$f"
}
ES_SUM="$OUT_DIR/es_summary.csv"
OS_SUM="$OUT_DIR/os_summary.csv"

ES_AGG=$(read_csv "$ES_SUM" "ES-agg")
ES_KNN=$(read_csv "$ES_SUM" "ES-knn")
OS_AGG=$(read_csv "$OS_SUM" "OS-agg")
OS_KNN=$(read_csv "$OS_SUM" "OS-knn")

# ========= 3) Extrair números =========
# campos: scenario,avg,p50,p95,min,max
get_col() { echo "$1" | awk -F, -v c="$2" '{print $c}'; }

ES_AGG_AVG=$(get_col "$ES_AGG" 2); ES_KNN_AVG=$(get_col "$ES_KNN" 2)
OS_AGG_AVG=$(get_col "$OS_AGG" 2); OS_KNN_AVG=$(get_col "$OS_KNN" 2)

# ========= 4) Calcular speedups =========
spdup() { awk -v a="$1" -v b="$2" 'BEGIN{ if(a==0||b==0){print "NA"} else {printf "%.2fx", (a/b)} }'; }
DIFF_PCT() { awk -v a="$1" -v b="$2" 'BEGIN{ if(a==0||b==0){print "NA"} else {printf "%.1f%%", ((b-a)/a)*100} }'; }

# speedup >1.00x => primeiro é mais lento (tempo/tempo). vamos também gerar “quem vence”.
SPD_AGG=$(spdup "$ES_AGG_AVG" "$OS_AGG_AVG")
SPD_KNN=$(spdup "$ES_KNN_AVG" "$OS_KNN_AVG")

WIN_AGG=$(awk -v es="$ES_AGG_AVG" -v os="$OS_AGG_AVG" 'BEGIN{print (es<os)?"ES":"OS"}')
WIN_KNN=$(awk -v es="$ES_KNN_AVG" -v os="$OS_KNN_AVG" 'BEGIN{print (es<os)?"ES":"OS"}')

# ========= 5) Checar mapeamento/ajustes para explicar =========
# ES mapping
ES_MAP=$(curl -s "$ES_HOST/$INDEX/_mapping")
ES_VEC_TYPE=$(echo "$ES_MAP" | sed 's/ //g' | tr -d '\n' | sed 's/{"[^"]*"://' \
  | sed 's/.*"embedding":{"type":"\([^"]*\)".*/\1/' )

# OS mapping + settings
OS_MAP=$(curl -s -k -u "$OS_USER:$OS_PASS" "$OS_HOST/$INDEX/_mapping")
OS_VEC_TYPE=$(echo "$OS_MAP" | sed 's/ //g' | tr -d '\n' | sed 's/{"[^"]*"://' \
  | sed 's/.*"embedding":{"type":"\([^"]*\)".*/\1/' )
OS_SET=$(curl -s -k -u "$OS_USER:$OS_PASS" "$OS_HOST/$INDEX/_settings")
OS_KNN_ENABLED=$(echo "$OS_SET" | sed 's/ //g' | tr -d '\n' | sed 's/{"[^"]*"://' \
  | sed -n 's/.*"index.knn":"\{0,1\}\([^",}]*\).*/\1/p' )
if [ -z "${OS_KNN_ENABLED:-}" ]; then OS_KNN_ENABLED=$(echo "$OS_SET" | grep -o '"index.knn"[^,}]*' | tail -n1 | awk -F: '{print $2}' | tr -d '"'); fi

# ========= 6) CSV combinado =========
COMB="$OUT_DIR/combined_summary.csv"
{
  echo "engine,scenario,avg,p50,p95,min,max"
  echo "ES,agg,$(echo "$ES_AGG" | cut -d, -f2- )"
  echo "ES,knn,$(echo "$ES_KNN" | cut -d, -f2- )"
  echo "OS,agg,$(echo "$OS_AGG" | cut -d, -f2- )"
  echo "OS,knn,$(echo "$OS_KNN" | cut -d, -f2- )"
} > "$COMB"

# ========= 7) Análise textual =========
pct() { awk -v a="$1" -v b="$2" 'BEGIN{ if(a==0||b==0){print "NA"} else {printf "%.1f%%", (1-b/a)*100} }'; }
AGG_GAIN=$(pct "$ES_AGG_AVG" "$OS_AGG_AVG")
KNN_GAIN=$(pct "$ES_KNN_AVG" "$OS_KNN_AVG")

analysis() {
  echo "== Resumo numérico =="
  printf "ES-agg avg: %s s | OS-agg avg: %s s | vencedor: %s | ganho: %s\n" "$ES_AGG_AVG" "$OS_AGG_AVG" "$WIN_AGG" "$AGG_GAIN"
  printf "ES-knn avg: %s s | OS-knn avg: %s s | vencedor: %s | ganho: %s\n" "$ES_KNN_AVG" "$OS_KNN_AVG" "$WIN_KNN" "$KNN_GAIN"
  echo

  echo "== Interpretação técnica =="
  echo "- Vetores:"
  echo "  • ES: embedding = ${ES_VEC_TYPE:-?}  → busca vetorial feita com script_score (cosineSimilarity), tipicamente varredura total (exata)."
  echo "  • OS: embedding = ${OS_VEC_TYPE:-?}  + index.knn=${OS_KNN_ENABLED:-?}  → usa kNN nativo (HNSW, aproximação por grafo)."
  echo
  if [ "$WIN_KNN" = "OS" ]; then
    cat <<'TXT'
- Por que OS é mais rápido no kNN?
  • O OpenSearch usa índice ANN (HNSW) nativo para `knn_vector`: ele não compara o vetor de consulta com **todos** os documentos;
    navega no grafo e compara só candidatos prováveis. Isso reduz muito o custo conforme a coleção cresce.
  • No Elasticsearch, com `dense_vector` + `script_score`, o caminho padrão é varredura com exatidão (brute force). Em coleções pequenas,
    a diferença pode ser pequena; mas com 100k+ docs, o HNSW tende a abrir vantagem grande.
TXT
  else
    cat <<'TXT'
- Por que ES ficou mais rápido no kNN (neste teste)?
  • Em bases pequenas, a sobrecarga de HTTPS + autenticação no OS e efeitos de cache podem empatar ou até inverter o resultado.
  • Verifique também:
      - K e dimensão (k/DIMS) baixos podem reduzir a vantagem do ANN.
      - Warmup: rode o bench duas vezes; a segunda rodada costuma estabilizar caches.
      - Se o índice OS não estiver com `index.knn: true` ou o campo não for `knn_vector`, ele não usará o HNSW.
TXT
  fi
  echo
  echo "- Agregações:"
  echo "  • Ambos usam estruturas invertidas do Lucene; desempenho tende a ser parecido."
  echo "  • Diferenças aqui geralmente vêm de shardização/replicas, cache quente, e I/O local. Para fairness, mantenha 1 shard e 0 réplicas em lab."
  echo
  echo "== Próximos passos p/ comparação mais 'real' =="
  echo "  1) Aumente o volume: DOCS=100000 em ambos; repita o bench."
  echo "  2) Aqueça cache: rode cada cenário 1x antes de medir."
  echo "  3) Fixe condições: 1 shard, 0 replicas, refresh_interval='-1' durante ingestão."
  echo
}

# ========= 8) Report Markdown =========
REPORT="$OUT_DIR/report.md"
{
  echo "# Benchmark ES vs OpenSearch — $(date +'%Y-%m-%d %H:%M:%S')"
  echo
  echo "## Parâmetros"
  echo "- Runs (repetições): **$N**"
  echo "- Top-K (kNN): **$K**"
  echo "- Dimensões do vetor: **$DIMS**"
  echo "- Índice: **$INDEX**"
  echo
  echo "## Resultados (média de latência em segundos)"
  echo ""
  echo "| Engine | Cenário | avg | p50 | p95 | min | max |"
  echo "|-------:|:-------|----:|----:|----:|----:|----:|"
  awk -F, 'NR>1{printf("| %s | %s | %.4f | %.4f | %.4f | %.4f | %.4f |\n",$1,$2,$3,$4,$5,$6,$7)}' "$COMB"
  echo
  echo "## Quem venceu?"
  echo "- **Agregação:** $WIN_AGG  (ganho vs outro: $AGG_GAIN)"
  echo "- **kNN:** $WIN_KNN  (ganho vs outro: $KNN_GAIN)"
  echo
  echo "## Explicação técnica"
  echo "- **Elasticsearch** usa \`dense_vector\` + \`script_score\` (busca exata)."
  echo "- **OpenSearch** usa \`knn_vector\` com \`index.knn: true\` (ANN/HNSW)."
  echo
  if [ "$WIN_KNN" = "OS" ]; then
    echo "> O HNSW do OS evita varredura completa e tende a escalar melhor para kNN."
  else
    echo "> Em bases pequenas/caches frios, a sobrecarga de HTTPS/Auth e efeitos de cache podem favorecer ES. Verifique o mapping e aqueça caches."
  fi
  echo
  echo "## Arquivos gerados"
  echo "- \`$COMB\` (summary combinado)"
  echo "- \`$OUT_DIR/es_summary.csv\`, \`$OUT_DIR/os_summary.csv\`"
  echo "- \`$OUT_DIR/es_*_raw.csv\`, \`$OUT_DIR/os_*_raw.csv\`"
} > "$REPORT"

# ========= 9) Console: resumo + análise =========
echo
echo "${BOLD}== Summary combinado (avg em s) ==${RST}"
column -s, -t "$COMB" | sed '1s/^/'"${DIM}"'/;1s/$/'"${RST}"'/'
echo
printf "${BOLD}Agregação:${RST} vencedor: %s  | ES avg=%s  OS avg=%s  | speedup ES/OS=%s  | ganho=%s\n" \
  "$WIN_AGG" "$ES_AGG_AVG" "$OS_AGG_AVG" "$SPD_AGG" "$AGG_GAIN"
printf "${BOLD}kNN:${RST}        vencedor: %s  | ES avg=%s  OS avg=%s  | speedup ES/OS=%s  | ganho=%s\n" \
  "$WIN_KNN" "$ES_KNN_AVG" "$OS_KNN_AVG" "$SPD_KNN" "$KNN_GAIN"

echo
analysis

echo
echo "${CYA}Relatório:${RST} $REPORT"
echo "${CYA}CSVs:${RST}     $COMB"
