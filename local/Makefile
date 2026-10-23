# Bring the stack up on a local kind cluster with plain Helm (no Argo CD).
# Chart versions are read from argocd/apps/*.yaml so local == GitOps.
#
#   make -C local up        # cluster + full stack + demo service
#   make -C local grafana   # http://localhost:3000 (admin / admin)
#   make -C local down

SHELL := /usr/bin/env bash
.SHELLFLAGS := -euo pipefail -c
.DEFAULT_GOAL := help

ROOT    := $(abspath ..)
CLUSTER := observability
NS      := monitoring
APPS    := $(ROOT)/argocd/apps

version = $(shell yq '.spec.sources[0].targetRevision' $(APPS)/$(1).yaml)
repo    = $(shell yq '.spec.sources[0].repoURL' $(APPS)/$(1).yaml)
HELM    := helm upgrade --install --namespace $(NS) --create-namespace --wait --timeout 10m

.PHONY: help
help: ## Show targets
	@grep -hE '^[a-zA-Z_-]+:.*?## ' $(MAKEFILE_LIST) | awk 'BEGIN {FS = ":.*?## "}; {printf "  \033[36m%-12s\033[0m %s\n", $$1, $$2}'

.PHONY: up
up: cluster secrets stack config demo ## Create cluster and deploy everything
	@echo; echo "Done. Run 'make -C local grafana' and open http://localhost:3000 (admin/admin)."

.PHONY: cluster
cluster: ## Create the kind cluster
	@kind get clusters | grep -qx $(CLUSTER) || kind create cluster --config kind-config.yaml
	kubectl config use-context kind-$(CLUSTER)

.PHONY: secrets
secrets: ## Create placeholder secrets (Grafana admin, Alertmanager receivers)
	kubectl create namespace $(NS) --dry-run=client -o yaml | kubectl apply -f -
	kubectl -n $(NS) create secret generic grafana-admin \
	  --from-literal=admin-user=admin --from-literal=admin-password=admin \
	  --dry-run=client -o yaml | kubectl apply -f -
	# Dummy receiver credentials: notifications will fail to send, routing still works.
	kubectl apply -f $(ROOT)/alertmanager/secret.example.yaml

.PHONY: stack
stack: ## Install the Helm charts in dependency order
	$(HELM) kps kube-prometheus-stack --repo $(call repo,kube-prometheus-stack) \
	  --version $(call version,kube-prometheus-stack) \
	  -f $(ROOT)/values/kube-prometheus-stack.yaml -f values/kube-prometheus-stack.yaml \
	  -f $(ROOT)/alertmanager/values.yaml
	$(HELM) vmsingle victoria-metrics-single --repo $(call repo,victoria-metrics) \
	  --version $(call version,victoria-metrics) \
	  -f $(ROOT)/values/victoria-metrics-single.yaml -f values/victoria-metrics-single.yaml
	$(HELM) loki loki --repo $(call repo,loki) --version $(call version,loki) \
	  -f $(ROOT)/values/loki.yaml -f values/loki.yaml
	$(HELM) alloy alloy --repo $(call repo,alloy) --version $(call version,alloy) \
	  -f $(ROOT)/values/alloy.yaml -f values/alloy.yaml

.PHONY: config
config: ## Apply alert rules and dashboards
	kubectl apply --server-side -k $(ROOT)/deploy/config

.PHONY: demo
demo: ## Deploy the instrumented example-api and a load generator
	kubectl apply -f $(ROOT)/local/example-api.yaml

.PHONY: grafana
grafana: ## Port-forward Grafana to localhost:3000
	kubectl -n $(NS) port-forward svc/grafana 3000:80

.PHONY: prometheus
prometheus: ## Port-forward Prometheus to localhost:9090
	kubectl -n $(NS) port-forward svc/kps-prometheus 9090:9090

.PHONY: alertmanager
alertmanager: ## Port-forward Alertmanager to localhost:9093
	kubectl -n $(NS) port-forward svc/kps-alertmanager 9093:9093

.PHONY: down
down: ## Delete the kind cluster
	kind delete cluster --name $(CLUSTER)
