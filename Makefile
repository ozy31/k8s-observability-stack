# Checks run by CI — run `make ci` locally before pushing.
# Requires: yq (mikefarah v4), jq, helm, promtool, amtool, kubeconform,
# yamllint, sloth, alloy. `make tools` prints what is missing.

SHELL := /usr/bin/env bash
.SHELLFLAGS := -euo pipefail -c
.DEFAULT_GOAL := help

CRD_CATALOG := https://raw.githubusercontent.com/datreeio/CRDs-catalog/main/{{.Group}}/{{.ResourceKind}}_{{.ResourceAPIVersion}}.json

.PHONY: help
help: ## Show targets
	@grep -hE '^[a-zA-Z_-]+:.*?## ' $(MAKEFILE_LIST) | awk 'BEGIN {FS = ":.*?## "}; {printf "  \033[36m%-18s\033[0m %s\n", $$1, $$2}'

.PHONY: tools
tools: ## Check required CLI tools are installed
	@for t in yq jq helm promtool amtool kubeconform yamllint sloth alloy kubectl; do \
	  command -v $$t >/dev/null && printf "  ok       %s\n" $$t || printf "  MISSING  %s\n" $$t; done

.PHONY: lint
lint: ## yamllint the repository
	yamllint --strict .

.PHONY: rules
rules: ## Extract rule groups from PrometheusRule CRDs into build/rules
	./scripts/extract-rules.sh

.PHONY: rules-check
rules-check: rules ## promtool check rules + severity/annotation policy
	promtool check rules build/rules/*.yaml
	./scripts/check-rules-metadata.sh

.PHONY: rules-test
rules-test: rules ## promtool unit tests in tests/
	promtool test rules tests/*.yaml

.PHONY: slo-generate
slo-generate: ## Regenerate slo/generated/ from the Sloth spec
	sloth generate -i slo/example-api.sloth.yaml -o slo/generated/example-api.yaml

.PHONY: slo-check
slo-check: ## Fail if slo/generated/ is stale
	sloth validate -i slo/example-api.sloth.yaml
	mkdir -p build
	sloth generate -i slo/example-api.sloth.yaml -o build/sloth-example-api.yaml
	diff -u slo/generated/example-api.yaml build/sloth-example-api.yaml

.PHONY: alertmanager-check
alertmanager-check: ## amtool check-config + routing tree assertions
	./scripts/check-alertmanager.sh

.PHONY: dashboards-check
dashboards-check: ## Validate dashboard JSON and the PromQL inside it
	./scripts/validate-dashboards.sh

.PHONY: alloy-check
alloy-check: ## alloy validate the log pipeline in values/alloy.yaml
	./scripts/check-alloy.sh

.PHONY: template
template: ## helm template every Application (prod + local values)
	./scripts/helm-template.sh
	LOCAL=1 ./scripts/helm-template.sh
	kubectl kustomize deploy/config > build/config.yaml

.PHONY: kubeconform
kubeconform: template ## Validate rendered manifests against Kubernetes + CRD schemas
	kubeconform -strict -summary -ignore-missing-schemas \
	  -schema-location default -schema-location '$(CRD_CATALOG)' \
	  build/manifests/*.yaml build/manifests-local/*.yaml build/config.yaml \
	  argocd/*.yaml argocd/apps/*.yaml argocd/optional/*.yaml \
	  alertmanager/secret.example.yaml alertmanager/externalsecret.yaml local/example-api.yaml

.PHONY: ci
ci: lint rules-check rules-test slo-check alertmanager-check dashboards-check alloy-check kubeconform ## Everything CI runs

.PHONY: clean
clean: ## Remove build output
	rm -rf build
