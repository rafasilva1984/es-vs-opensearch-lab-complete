# Elasticsearch vs OpenSearch — Laboratório Comparativo

Este laboratório permite subir **Elasticsearch** e **OpenSearch** lado a lado, ingerir dados simulados e rodar **benchmarks comparativos** de consultas de agregação e busca vetorial (kNN).

## 📦 Pré-requisitos
- Docker + Docker Compose
- curl, awk, bash (já inclusos em WSL / Linux / Git Bash)
- **Não requer `jq` ou Python local** — tudo roda via `curl` e containers.

---

## 🚀 Subindo o ambiente

### Elasticsearch
```bash
cd es
docker compose up -d
```
Acessar Kibana em: [http://localhost:5601](http://localhost:5601)

### OpenSearch
```bash
cd os
docker compose up -d
```
Acessar OpenSearch Dashboards em: [https://localhost:5602](https://localhost:5602)  
Usuário: `admin`  
Senha: `Admin123!ChangeMe`

---

## 📥 Ingestão de dados

Scripts de ingestão já estão prontos. Eles criam o índice `logs` e populam documentos com embeddings simulados.

### Elasticsearch
```bash
./es/load_data.sh
```

### OpenSearch
```bash
./os/load_data.sh
```

### Parâmetros opcionais
Você pode ajustar o volume e o tamanho do lote:
```bash
DOCS=50000 BATCH_DOCS=2000 ./es/load_data.sh
DOCS=50000 BATCH_DOCS=2000 ./os/load_data.sh
```
- `DOCS`: número total de documentos a ingerir.  
- `BATCH_DOCS`: número de docs enviados por requisição `_bulk`.  

---

## 📊 Benchmarks

### Elasticsearch
```bash
./bench/run_bench_es.sh
```
- Executa **agregação** e **busca vetorial (dense_vector + script_score)**.
- Salva resultados em `bench/results/es_*`.

### OpenSearch
```bash
./bench/run_bench_os.sh
```
- Executa **agregação** e **busca vetorial (knn_vector + HNSW)**.
- Salva resultados em `bench/results/os_*`.

---

## ⚖️ Benchmark Comparativo

Para rodar **ambos** e gerar relatório comparando ES x OS:

```bash
./bench/run_bench_compare.sh
```

Este script:
- Executa ES e OS em paralelo (agregação e kNN).  
- Calcula métricas de **latência média, p50, p95, min, max**.  
- Gera arquivos CSV com latências individuais e médias:  
  - `bench/results/es_summary.csv`  
  - `bench/results/os_summary.csv`  
  - `bench/results/combined_summary.csv`  
- Cria um **relatório automático em Markdown**:  
  - `bench/results/report.md`

### Exemplo de saída no console
```
== Summary combinado (avg em s) ==
engine  scenario  avg    p50    p95    min    max
ES      agg       0.012  0.011  0.020  0.010  0.031
ES      knn       0.028  0.027  0.041  0.025  0.052
OS      agg       0.011  0.010  0.019  0.009  0.029
OS      knn       0.014  0.013  0.022  0.012  0.034

Agregação: vencedor: OS | ganho vs ES: ~8.3%
kNN:       vencedor: OS | ganho vs ES: ~50.0%
```

### Trecho do relatório (`report.md`)
```markdown
## Quem venceu?
- **Agregação:** OS  (ganho vs ES: 8.3%)
- **kNN:** OS  (ganho vs ES: 50.0%)

## Explicação rápida
- **OpenSearch kNN**: usa `knn_vector` com ANN/HNSW (aproximação por grafo), evitando varredura completa → mais rápido em bases grandes.
- **Elasticsearch kNN**: usa `dense_vector` + `script_score` (cosineSimilarity), que é exato mas faz scan de todos os docs → tende a ficar mais lento conforme cresce.
```

---

## 📈 Interpretação dos resultados

- **Agregações** → desempenho parecido, pois ambos usam estruturas invertidas do Lucene. Diferenças vêm de cache, shards e I/O.  
- **Busca vetorial (kNN)** →  
  - OpenSearch se destaca pelo suporte nativo ao HNSW (ANN).  
  - Elasticsearch ainda depende de `script_score`, que é exato, mas escala mal para grandes volumes.  
- Em bases pequenas, a diferença pode ser pequena ou até inverter por efeito de cache/overhead TLS.  
- Em bases maiores (100k+ docs), a vantagem do OS deve crescer.

---

## 🔮 Próximos passos sugeridos

1. Aumentar `DOCS` para 100k+ e refazer os benchmarks.  
2. Fazer **warmup** (rodar 1 vez antes de medir).  
3. Configurar índices com **1 shard e 0 replicas** em lab para evitar variabilidade.  
4. Comparar custo/licenciamento:  
   - Elasticsearch (Elastic License 2.0).  
   - OpenSearch (Apache 2.0, open source completo).  

---

## 📂 Estrutura de resultados

```
bench/results/
├── es_summary.csv
├── os_summary.csv
├── combined_summary.csv
├── report.md
├── es_agg_raw.csv
├── es_knn_raw.csv
├── os_agg_raw.csv
├── os_knn_raw.csv
```
