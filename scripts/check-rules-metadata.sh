#!/usr/bin/env bash
# Policy checks promtool does not do: every alert must carry a known
# severity and the annotations a responder needs.
set -euo pipefail

cd "$(dirname "$0")/.."
fail=0
for f in build/rules/*.yaml; do
  while IFS=$'\t' read -r alert severity summary runbook; do
    if [[ ! "$severity" =~ ^(critical|warning|info)$ ]]; then
      echo "::error file=$f::$alert has invalid severity '$severity'"; fail=1
    fi
    if [[ "$summary" == "null" ]]; then
      echo "::error file=$f::$alert has no summary annotation"; fail=1
    fi
    if [[ "$runbook" == "null" ]]; then
      echo "::error file=$f::$alert has no runbook_url annotation"; fail=1
    fi
  done < <(yq -r '.groups[].rules[] | select(has("alert")) | [.alert, .labels.severity, .annotations.summary, .annotations.runbook_url] | @tsv' "$f")
done
[[ $fail -eq 0 ]] && echo "rule metadata OK"
exit $fail
