#!/usr/bin/env bash
# Validate Grafana dashboards:
#   1. valid JSON with uid/title/panels, unique uids and panel ids
#   2. no hard-coded datasource UIDs (everything goes through variables)
#   3. every PromQL query parses (checked with promtool via a throwaway rule file)
set -euo pipefail

cd "$(dirname "$0")/.."
mkdir -p build
fail=0

for f in dashboards/*.json; do
  jq -e . "$f" >/dev/null || { echo "::error file=$f::invalid JSON"; fail=1; continue; }
  jq -e '(.uid | type == "string" and length > 0) and (.title | length > 0) and (.panels | length > 0)' "$f" >/dev/null \
    || { echo "::error file=$f::missing uid/title/panels"; fail=1; }
  dup=$(jq '[.panels[].id] | length - (unique | length)' "$f")
  [[ "$dup" == 0 ]] || { echo "::error file=$f::duplicate panel ids"; fail=1; }
  hard=$(jq -r '[.. | objects | select(has("datasource")) | .datasource | objects | .uid // empty
                 | select(startswith("$") | not) | select(. != "-- Grafana --")] | unique | join(",")' "$f")
  [[ -z "$hard" ]] || { echo "::error file=$f::hard-coded datasource uid(s): $hard"; fail=1; }
  echo "ok   $f ($(jq '.panels | length' "$f") panels)"
done

dups=$(jq -r '.uid' dashboards/*.json | sort | uniq -d)
[[ -z "$dups" ]] || { echo "::error::duplicate dashboard uid(s): $dups"; fail=1; }

# PromQL syntax check: wrap every Prometheus-datasource expression in a
# recording rule and let promtool parse it.
out=build/dashboard-promql.yaml
{
  echo "groups:"
  echo "  - name: dashboard-queries"
  echo "    rules:"
  jq -r '.panels[] | select(.datasource.type == "prometheus") | .targets[]?
         | (.datasource.type // "prometheus") as $t | select($t == "prometheus") | .expr | tojson' dashboards/*.json \
    | sed -e 's/\$__rate_interval/5m/g' -e 's/\$__interval/1m/g' -e 's/\$__range/1h/g' \
          -e 's/\$node_hourly_price/0.1/g' -e 's/\$node_vcpu/4/g' -e 's/\$node_memory_gib/16/g' \
    | sed -e 's/^/      - record: dashboard:query:check\n        expr: /'
} > "$out"
promtool check rules --lint=none "$out" >/dev/null || { promtool check rules --lint=none "$out"; fail=1; }
echo "PromQL in dashboards: $(grep -c 'record:' "$out") queries parsed"

exit $fail
