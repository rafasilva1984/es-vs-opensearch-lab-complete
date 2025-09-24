#!/usr/bin/env bash
set -euo pipefail
curl -s http://localhost:${ES_HTTP:-9200}/_cluster/health?pretty
