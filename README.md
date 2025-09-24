# Laboratório COMPLETO — Elasticsearch x OpenSearch (Observabilidade na Prática)

> **Atenção**: segurança desativada para fins de estudo **(NÃO use em produção)**.

## Requisitos
- Docker + Docker Compose
- Python 3.8+
- `curl`

## Estrutura
```
es-vs-opensearch-lab-complete/
├─ es/                    # Elasticsearch + Kibana
│  ├─ docker-compose.yml
│  └─ load_data.sh
├─ os/                    # OpenSearch + Dashboards
│  ├─ docker-compose.yml
│  └─ load_data.sh
├─ bench/                 # Scripts de benchmark e geração de docs
│  ├─ gen_docs.py
│  ├─ run_bench_es.sh
│  ├─ run_bench_os.sh
│  └─ report_template.md
├─ queries/               # Exemplos de consultas (ES|QL e PPL)
│  ├─ es_esql_examples.txt
│  └─ os_ppl_examples.txt
├─ scripts/               # Utilitários
│  ├─ start.sh / stop.sh
│  ├─ health_es.sh / health_os.sh
│  └─ *.bat (para Windows)
├─ assets/                # Dashboards de exemplo para importar
│  ├─ kibana_export.ndjson
│  └─ opensearch_dashboards_sample.json
├─ rally/                 # Instruções Rally
├─ opensearch-benchmark/  # Instruções OS Benchmark
└─ README.md              # Este arquivo
```

## 1) Subir os ambientes

### Elasticsearch + Kibana
```bash
cd es-vs-opensearch-lab-complete/es
docker compose up -d
```

### OpenSearch + Dashboards
```bash
cd ../os
docker compose up -d
```

> Para desligar tudo e limpar volumes:
```bash
cd es-vs-opensearch-lab-complete/es && docker compose down -v
cd ../os && docker compose down -v
```

## 2) Ingestão de dados (200k docs por padrão)
Na raiz do projeto:

### Elasticsearch
```bash
./es/load_data.sh
```

### OpenSearch
```bash
./os/load_data.sh
```

Variáveis opcionais:
```bash
DOCS=500000 DIMS=256 ./es/load_data.sh
DOCS=500000 DIMS=256 ./os/load_data.sh
```

## 3) Consultas exemplares
- Acesse **Kibana** em [http://localhost:5601](http://localhost:5601) e cole o conteúdo de `queries/es_esql_examples.txt` no console ES|QL.
- Acesse **OpenSearch Dashboards** em [http://localhost:5602](http://localhost:5602) e cole `queries/os_ppl_examples.txt` no console PPL.

## 4) Benchmarks
Na raiz do repositório, rode:

```bash
./bench/run_bench_es.sh
./bench/run_bench_os.sh
```

Repita 10–30 vezes e anote resultados em `bench/report_template.md`.

## 5) Health-checks
```bash
./scripts/health_es.sh
./scripts/health_os.sh
```

## 6) Dashboards de exemplo
- **Kibana**: importe `assets/kibana_export.ndjson`
- **OpenSearch Dashboards**: importe `assets/opensearch_dashboards_sample.json`

## 7) Benchmark oficial (opcional)
- **Rally**: veja `rally/README.md`
- **OpenSearch Benchmark**: veja `opensearch-benchmark/README.md`

## Troubleshooting
- **Containers reiniciando**: reduza heap no `.env` (ou use compose.light.yml).
- **Bulk lento**: reduza `DOCS`, rode em SSD.
- **kNN lento**: ajuste parâmetros HNSW (`M`, `efSearch`, `num_candidates`).
- **Portas em uso**: altere variáveis no `.env` (ES_HTTP, OS_HTTP, etc).

## Segurança (produção)
- Elasticsearch: habilite `xpack.security.*`, TLS, usuários/roles.
- OpenSearch: mantenha Security ativo, configure certificados e senhas.

---
© Observabilidade na Prática — By Rafa Silva
