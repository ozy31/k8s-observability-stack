#!/usr/bin/env bash
# Download pinned versions of the CLI tools used by `make ci` into ./bin.
# Works on linux/darwin, amd64/arm64. Used by CI; handy locally too:
#   ./scripts/install-tools.sh && export PATH="$PWD/bin:$PATH"
set -euo pipefail

PROMETHEUS_VERSION=3.15.1
ALERTMANAGER_VERSION=0.34.1
KUBECONFORM_VERSION=0.8.0
YQ_VERSION=4.54.1
SLOTH_VERSION=0.16.0
ALLOY_VERSION=1.21.1

cd "$(dirname "$0")/.."
BIN=${BIN:-$PWD/bin}
mkdir -p "$BIN"
os=$(uname -s | tr '[:upper:]' '[:lower:]')
arch=$(uname -m); case "$arch" in x86_64) arch=amd64 ;; aarch64|arm64) arch=arm64 ;; esac
tmp=$(mktemp -d); trap 'rm -rf "$tmp"' EXIT
gh=https://github.com

fetch() { curl -fsSL --retry 3 "$1" -o "$2"; }

fetch "$gh/prometheus/prometheus/releases/download/v$PROMETHEUS_VERSION/prometheus-$PROMETHEUS_VERSION.$os-$arch.tar.gz" "$tmp/prom.tgz"
tar -xzf "$tmp/prom.tgz" -C "$tmp" && cp "$tmp/prometheus-$PROMETHEUS_VERSION.$os-$arch/promtool" "$BIN/"

fetch "$gh/prometheus/alertmanager/releases/download/v$ALERTMANAGER_VERSION/alertmanager-$ALERTMANAGER_VERSION.$os-$arch.tar.gz" "$tmp/am.tgz"
tar -xzf "$tmp/am.tgz" -C "$tmp" && cp "$tmp/alertmanager-$ALERTMANAGER_VERSION.$os-$arch/amtool" "$BIN/"

fetch "$gh/yannh/kubeconform/releases/download/v$KUBECONFORM_VERSION/kubeconform-$os-$arch.tar.gz" "$tmp/kc.tgz"
tar -xzf "$tmp/kc.tgz" -C "$BIN" kubeconform

fetch "$gh/mikefarah/yq/releases/download/v$YQ_VERSION/yq_${os}_$arch" "$BIN/yq"
fetch "$gh/slok/sloth/releases/download/v$SLOTH_VERSION/sloth-$os-$arch" "$BIN/sloth"
fetch "$gh/grafana/alloy/releases/download/v$ALLOY_VERSION/alloy-$os-$arch.zip" "$tmp/alloy.zip"
unzip -oq "$tmp/alloy.zip" -d "$tmp" && cp "$tmp/alloy-$os-$arch" "$BIN/alloy"
chmod +x "$BIN"/*

echo "installed into $BIN:"
"$BIN/promtool" --version | head -1
"$BIN/amtool" --version | head -1
echo "kubeconform $("$BIN/kubeconform" -v)"
"$BIN/yq" --version
echo "sloth $("$BIN/sloth" version)"
"$BIN/alloy" --version | head -1
