# Laboratório COMPLETO — Elasticsearch x OpenSearch (Observabilidade na Prática)

> **Atenção**: segurança desativada para fins de estudo **(NÃO use em produção)**.

## Requisitos
- Docker + Docker Compose
- Python 3.8+
- `curl`, `make` (recomendado)
- (Opcional) `pipx` para instalar Rally / OpenSearch Benchmark

## Passo a passo rápido
```bash
# subir
make up            # ou: make light-up para máquinas com menos RAM
# ingestão
make load-es
make load-os
# benchmark rápido
make bench-es
make bench-os
# status dos clusters
make status
# parar e apagar volumes
make down
```

Variáveis ajustáveis no `.env`:
- `DOCS`, `DIMS` (dataset sintético)
- `ES_HEAP`, `OS_HEAP` (heap da JVM)
- Portas locais (evite conflitos)

## Interfaces
- Kibana: http://localhost:${KIBANA:-5601}
- OpenSearch Dashboards: http://localhost:${OS_DASH:-5602}

## Dashboards/Objetos
Importe exemplos:
- Kibana: `assets/kibana_export.ndjson`
- OpenSearch Dashboards: `assets/opensearch_dashboards_sample.json`

## Benchmark oficial (opcional)
- **Rally**: veja `rally/README.md`
- **OpenSearch Benchmark**: veja `opensearch-benchmark/README.md`

## Troubleshooting
- **Containers reiniciando**: reduza heap (`ES_HEAP/OS_HEAP=1g`) ou use `make light-up`.
- **Bulk lento**: verifique disco/IO; reduza `DOCS`; rode em SSD.
- **kNN muito lento**: reduza `num_candidates` (ES) ou `k` (OS); ajuste HNSW (`M`, `efSearch`). 
- **Kibana/Dashboards não abrem**: aguarde 30–60s; cheque `docker logs`.
- **Porta em uso**: altere portas no `.env` (ex.: `ES_HTTP=9220`, `OS_HTTP=9221`).

## Segurança (produção)
- Elasticsearch: habilite `xpack.security.*`, TLS e usuários/roles.
- OpenSearch: mantenha o plugin Security habilitado, configure senhas e certificados.

---
© Observabilidade na Prática — By Rafa Silva
