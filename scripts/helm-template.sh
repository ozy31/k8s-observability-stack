#!/usr/bin/env bash
# Render every Helm-based Argo CD Application exactly as Argo CD would:
# chart, repo, version and value files are read from argocd/apps/*.yaml and
# argocd/optional/*.yaml, so the Application manifests are the single source
# of truth for versions.
#
#   scripts/helm-template.sh          -> build/manifests/<app>.yaml
#   LOCAL=1 scripts/helm-template.sh  -> also layer local/values/<file> (kind)
set -euo pipefail

cd "$(dirname "$0")/.."
suffix=""; [[ "${LOCAL:-0}" == 1 ]] && suffix="-local"
out=build/manifests${suffix}
rm -rf "$out" && mkdir -p "$out"

for app in argocd/apps/*.yaml argocd/optional/*.yaml; do
  chart=$(yq '.spec.sources[0].chart // ""' "$app")
  [[ -z "$chart" ]] && continue
  name=$(yq '.metadata.name' "$app")
  repo=$(yq '.spec.sources[0].repoURL' "$app")
  version=$(yq '.spec.sources[0].targetRevision' "$app")
  release=$(yq '.spec.sources[0].helm.releaseName' "$app")
  ns=$(yq '.spec.destination.namespace' "$app")

  args=()
  while read -r vf; do
    vf=${vf#\$values/}
    args+=(-f "$vf")
    if [[ -n "$suffix" && -f "local/values/$(basename "$vf")" ]]; then
      args+=(-f "local/values/$(basename "$vf")")
    fi
  done < <(yq '.spec.sources[0].helm.valueFiles[]' "$app")

  echo "helm template $release $chart@$version ${args[*]}"
  helm template "$release" "$chart" --repo "$repo" --version "$version" \
    --namespace "$ns" "${args[@]}" \
    --api-versions monitoring.coreos.com/v1 \
    > "$out/$name.yaml"
done
