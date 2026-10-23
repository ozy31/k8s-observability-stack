#!/usr/bin/env bash
# Extract plain Prometheus rule files from PrometheusRule CRDs so that
# promtool can check and unit-test exactly what the operator will load.
#
#   alerts/foo.yaml (PrometheusRule)  ->  build/rules/foo.yaml (rule groups)
set -euo pipefail

cd "$(dirname "$0")/.."
out=build/rules
rm -rf "$out" && mkdir -p "$out"

for f in alerts/*.yaml slo/generated/*.yaml; do
  [[ "$(basename "$f")" == kustomization.yaml ]] && continue
  kind=$(yq 'select(document_index == 0) | .kind' "$f")
  if [[ "$kind" != "PrometheusRule" ]]; then
    echo "skip $f (kind: $kind)"
    continue
  fi
  name=$(basename "$f")
  [[ "$f" == slo/generated/* ]] && name="sloth-$name"
  yq '.spec' "$f" > "$out/$name"
  echo "extracted $f -> $out/$name"
done
