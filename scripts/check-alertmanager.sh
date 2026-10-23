#!/usr/bin/env bash
# Validate the Alertmanager config embedded in alertmanager/values.yaml:
#   1. amtool check-config (syntax, receivers, templates)
#   2. routing assertions from alertmanager/routes-test.txt
set -euo pipefail

cd "$(dirname "$0")/.."
dir=build/alertmanager
rm -rf "$dir" && mkdir -p "$dir"

yq '.alertmanager.templateFiles["notifications.tmpl"]' alertmanager/values.yaml > "$dir/notifications.tmpl"
# Point the template glob at the extracted file instead of the in-cluster path.
yq ".alertmanager.config | .templates = [\"$PWD/$dir/*.tmpl\"]" alertmanager/values.yaml > "$dir/alertmanager.yaml"

amtool check-config "$dir/alertmanager.yaml"

fail=0
while IFS='|' read -r expected labels; do
  [[ -z "${expected// }" || "$expected" == \#* ]] && continue
  expected=$(echo "$expected" | xargs)
  # shellcheck disable=SC2086
  if amtool config routes test --config.file="$dir/alertmanager.yaml" --verify.receivers="$expected" $labels >/dev/null; then
    echo "ok   $labels -> $expected"
  else
    got=$(amtool config routes test --config.file="$dir/alertmanager.yaml" $labels || true)
    echo "FAIL $labels -> expected $expected, got $got"; fail=1
  fi
done < alertmanager/routes-test.txt
exit $fail
