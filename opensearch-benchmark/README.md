# OpenSearch Benchmark — execução rápida (opcional)

## Instalação
```
pipx install opensearch-benchmark
```

## Executar benchmark contra cluster existente (localhost)
```
opensearch-benchmark execute-test   --workload=nyc_taxis   --target-hosts=localhost:9201
```

## Dicas
- Use `--pipeline=benchmark-only` se quiser apontar para cluster externo.
- Registre métricas de took, throughput e store size.
