#!/usr/bin/env bash
set -euo pipefail
curl -s http://localhost:${OS_HTTP:-9201}/_cluster/health?pretty
