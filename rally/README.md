# Elastic Rally — execução rápida (opcional)

## Instalação
Recomendado via pipx:
```
pipx install esrally
```

## Executar benchmark contra cluster existente (localhost)
```
esrally --pipeline=benchmark-only   --target-hosts=localhost:9200   --track=geonames
```

## Dicas
- Use `--test-mode` para uma corrida curta.
- Tracks populares: geonames, http_logs, nyc_taxis.
- Documente heap, CPU e disco para comparações justas.
