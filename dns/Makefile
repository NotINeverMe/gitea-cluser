# DNS management subproject (Namecheap)

.PHONY: help backup snapshot plan apply apply-dry evidence

SHELL := /bin/bash
ROOT := $(abspath ..)
EVIDENCE_DIR := $(ROOT)/compliance/evidence/dns

help: ## Show help
	@echo "DNS subproject Makefile"
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | awk 'BEGIN {FS = ":.*?## "}; {printf "  %-15s %s\n", $$1, $$2}'

backup: ## Export live DNS (getHosts) -> evidence + YAML snapshot
	@mkdir -p $(EVIDENCE_DIR)
	@./scripts/export.sh

snapshot: backup ## Alias for backup

plan: ## Diff: desired.records vs current live DNS -> evidence diff
	@./scripts/plan.sh

apply-dry: ## Dry-run apply from desired.records (prints curl only)
	@DRY_RUN=1 ./scripts/apply.sh

apply: ## Apply desired.records (REPLACES ALL HOSTS) requires CONFIRM_OVERWRITE=1
	@test "$(CONFIRM_OVERWRITE)" = "1" 2>/dev/null || (echo "Set CONFIRM_OVERWRITE=1 to proceed" && exit 1)
	@./scripts/apply.sh

evidence: ## Package latest evidence into a tarball under /tmp
	@./scripts/evidence-pack.sh

