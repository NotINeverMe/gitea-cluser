.PHONY: help sast deps secrets dast validate infra-checks infra-pen infra suite evidence

SHELL := /bin/bash
ROOT := $(abspath ..)
EVIDENCE_DIR := $(ROOT)/compliance/evidence/security

help: ## Show help
	@echo "Security suite Makefile"
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | awk 'BEGIN {FS = ":.*?## "}; {printf "  %-15s %s\n", $$1, $$2}'

sast: ## Run static analysis (semgrep, bandit, hadolint)
	@./scripts/sast-semgrep.sh
	@./scripts/sast-bandit.sh || true
	@./scripts/sast-hadolint.sh || true

deps: ## Dependency & filesystem scan (Trivy)
	@./scripts/trivy-fs.sh || true

secrets: ## Secrets scan (Gitleaks)
	@./scripts/secrets-scan.sh || true

dast: ## DAST quick checks (ZAP baseline + Nuclei)
	@./scripts/dast-zap-baseline.sh || true
	@./scripts/dast-nuclei.sh || true

validate: ## Deployment validation (health, headers, TLS)
	@./scripts/validate-deploy.sh || true

suite: ## Run full security suite and package evidence
	@mkdir -p $(EVIDENCE_DIR)
	@$(MAKE) sast
	@$(MAKE) deps
	@$(MAKE) secrets
	@$(MAKE) dast
	@$(MAKE) validate
	@$(MAKE) infra-checks
	@./scripts/evidence-pack.sh

evidence: ## Package security evidence into /tmp
	@./scripts/evidence-pack.sh

infra-checks: ## Infrastructure checks (Terraform scans + optional GCP enum)
	@./scripts/infra-terraform-scan.sh || true
	@./scripts/infra-gcp-enum.sh || true

infra-pen: ## Infrastructure pen tests (Nmap + TLS checks)
	@./scripts/infra-nmap.sh || true
	@./scripts/infra-ssl.sh || true

infra: ## Run infra checks and pen tests
	@$(MAKE) infra-checks
	@$(MAKE) infra-pen
