SHELL := /bin/bash

include .env

.PHONY: all up down clean status load-es load-os bench-es bench-os light-up

all: up

up:
	cd es && ES_JAVA_OPTS="-Xms$(ES_HEAP) -Xmx$(ES_HEAP)" docker compose up -d
	cd os && OPENSEARCH_JAVA_OPTS="-Xms$(OS_HEAP) -Xmx$(OS_HEAP)" docker compose up -d

light-up:
	cd es && ES_JAVA_OPTS="-Xms1g -Xmx1g" docker compose -f docker-compose.yml -f docker-compose.light.yml up -d
	cd os && OPENSEARCH_JAVA_OPTS="-Xms1g -Xmx1g" docker compose -f docker-compose.yml -f docker-compose.light.yml up -d

down:
	cd es && docker compose down -v
	cd os && docker compose down -v

status:
	@echo "== ES =="
	@echo "== ES ==" 
	@curl -s http://localhost:$(ES_HTTP)/_cluster/health?pretty || true
	@echo "== OS ==" 
	@curl -s http://localhost:$(OS_HTTP)/_cluster/health?pretty || true

load-es:
	ES_HOST=http://localhost:$(ES_HTTP) DOCS=$(DOCS) DIMS=$(DIMS) bash es/load_data.sh

load-os:
	OS_HOST=http://localhost:$(OS_HTTP) DOCS=$(DOCS) DIMS=$(DIMS) bash os/load_data.sh

bench-es:
	ES_HOST=http://localhost:$(ES_HTTP) bash bench/run_bench_es.sh

bench-os:
	OS_HOST=http://localhost:$(OS_HTTP) bash bench/run_bench_os.sh

clean:
	rm -rf es/data os/data
