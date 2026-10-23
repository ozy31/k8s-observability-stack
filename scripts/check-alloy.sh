#!/usr/bin/env bash
# Validate the Alloy pipeline embedded in values/alloy.yaml with `alloy validate`
# (catches unknown components/attributes, not just syntax).
set -euo pipefail

cd "$(dirname "$0")/.."
mkdir -p build
yq '.alloy.configMap.content' values/alloy.yaml > build/config.alloy
NODE_NAME=validate CLUSTER_NAME=validate alloy validate build/config.alloy
echo "alloy config OK"
