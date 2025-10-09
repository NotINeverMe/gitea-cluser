# Atlantis + Terragrunt GitOps Makefile
# CMMC 2.0: CM.L2-3.4.2 (Configuration Management)
# NIST SP 800-171: 3.4.2 (Baseline Configuration)

.PHONY: help setup start stop restart clean validate security-scan cost-estimate evidence backup restore

# Variables
PROJECT_ID ?= $(shell gcloud config get-value project 2>/dev/null || echo "gitea-project")
ENVIRONMENT ?= dev
ATLANTIS_VERSION = v0.27.0
TERRAGRUNT_VERSION = v0.52.0
TERRAFORM_VERSION = 1.6.0
EVIDENCE_BUCKET = gs://$(PROJECT_ID)-atlantis-evidence
STATE_BUCKET = gs://$(PROJECT_ID)-terraform-state
TIMESTAMP = $(shell date +%Y%m%d-%H%M%S)

# Color output
RED = \033[0;31m
GREEN = \033[0;32m
YELLOW = \033[1;33m
NC = \033[0m # No Color

help: ## Show this help message
	@echo "$(GREEN)Atlantis GitOps Makefile$(NC)"
	@echo ""
	@echo "Usage: make [target] [VARIABLE=value]"
	@echo ""
	@echo "Targets:"
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | awk 'BEGIN {FS = ":.*?## "}; {printf "  $(GREEN)%-20s$(NC) %s\n", $$1, $$2}'
	@echo ""
	@echo "Variables:"
	@echo "  $(YELLOW)PROJECT_ID$(NC)    GCP Project ID (current: $(PROJECT_ID))"
	@echo "  $(YELLOW)ENVIRONMENT$(NC)   Target environment (current: $(ENVIRONMENT))"
	@echo ""
	@echo "Security shortcuts:"
	@echo "  $(GREEN)security-suite$(NC)        Run full app+infra security suite (evidence)"
	@echo "  $(GREEN)security-infra$(NC)        Run infra checks + pen tests"
	@echo "  $(GREEN)security-dast$(NC)         Run ZAP + Nuclei + validation"
	@echo "  $(GREEN)dns-backup$(NC)            Backup Namecheap DNS (evidence)"
	@echo "  $(GREEN)dns-plan$(NC)              Diff desired vs live DNS"
	@echo "  $(GREEN)dns-apply-dry$(NC)         Dry-run Namecheap update"
	@echo "  $(GREEN)dns-apply$(NC)             Apply Namecheap update (danger)"

# ===== SETUP TARGETS =====

setup: ## Run complete setup for Atlantis GitOps
	@echo "$(GREEN)Starting Atlantis GitOps setup...$(NC)"
	@chmod +x scripts/setup-atlantis.sh
	@./scripts/setup-atlantis.sh
	@echo "$(GREEN)Setup complete!$(NC)"

setup-gcp: ## Setup GCP resources (buckets, service accounts)
	@echo "$(GREEN)Setting up GCP resources...$(NC)"
	@echo "Project ID: $(PROJECT_ID)"
	@$(MAKE) create-buckets
	@$(MAKE) create-service-account
	@$(MAKE) setup-iam
	@echo "$(GREEN)GCP setup complete!$(NC)"

create-buckets: ## Create GCS buckets for state and evidence
	@echo "$(YELLOW)Creating GCS buckets...$(NC)"
	@gsutil mb -p $(PROJECT_ID) -c STANDARD -l us-central1 -b on $(STATE_BUCKET) || true
	@gsutil versioning set on $(STATE_BUCKET)
	@gsutil mb -p $(PROJECT_ID) -c STANDARD -l us-central1 -b on $(EVIDENCE_BUCKET) || true
	@gsutil versioning set on $(EVIDENCE_BUCKET)
	@echo "$(GREEN)Buckets created$(NC)"

create-service-account: ## Create Atlantis service account
	@echo "$(YELLOW)Creating service account...$(NC)"
	@gcloud iam service-accounts create atlantis-terraform \
		--display-name="Atlantis Terraform Service Account" \
		--project=$(PROJECT_ID) || true
	@gcloud iam service-accounts keys create atlantis/gcp-sa.json \
		--iam-account=atlantis-terraform@$(PROJECT_ID).iam.gserviceaccount.com \
		--project=$(PROJECT_ID) || true
	@chmod 600 atlantis/gcp-sa.json
	@echo "$(GREEN)Service account created$(NC)"

setup-iam: ## Configure IAM roles for Atlantis
	@echo "$(YELLOW)Setting up IAM roles...$(NC)"
	@for role in \
		roles/compute.admin \
		roles/container.admin \
		roles/storage.admin \
		roles/iam.serviceAccountUser \
		roles/resourcemanager.projectIamAdmin; do \
		gcloud projects add-iam-policy-binding $(PROJECT_ID) \
			--member="serviceAccount:atlantis-terraform@$(PROJECT_ID).iam.gserviceaccount.com" \
			--role="$$role" \
			--condition=None || true; \
	done
	@echo "$(GREEN)IAM roles configured$(NC)"

generate-certs: ## Generate TLS certificates
	@echo "$(YELLOW)Generating TLS certificates...$(NC)"
	@mkdir -p atlantis/tls
	@openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
		-keyout atlantis/tls/key.pem \
		-out atlantis/tls/cert.pem \
		-subj "/CN=atlantis.gitea.local" \
		-addext "subjectAltName=DNS:atlantis.gitea.local,DNS:localhost"
	@chmod 600 atlantis/tls/key.pem
	@chmod 644 atlantis/tls/cert.pem
	@echo "$(GREEN)TLS certificates generated$(NC)"

# ===== ATLANTIS OPERATIONS =====

start: ## Start Atlantis services
	@echo "$(GREEN)Starting Atlantis services...$(NC)"
	@cd atlantis && docker-compose up -d
	@echo "$(GREEN)Atlantis is running at https://atlantis.gitea.local$(NC)"

stop: ## Stop Atlantis services
	@echo "$(YELLOW)Stopping Atlantis services...$(NC)"
	@cd atlantis && docker-compose down
	@echo "$(GREEN)Atlantis stopped$(NC)"

restart: ## Restart Atlantis services
	@echo "$(YELLOW)Restarting Atlantis services...$(NC)"
	@cd atlantis && docker-compose restart
	@echo "$(GREEN)Atlantis restarted$(NC)"

logs: ## View Atlantis logs
	@cd atlantis && docker-compose logs -f --tail=100

status: ## Check Atlantis status
	@echo "$(GREEN)Atlantis Status:$(NC)"
	@cd atlantis && docker-compose ps
	@echo ""
	@echo "$(GREEN)Health Check:$(NC)"
	@curl -s http://localhost:4141/healthz || echo "$(RED)Atlantis not reachable$(NC)"

# ===== VALIDATION TARGETS =====

validate: ## Validate all Terragrunt configurations
	@echo "$(GREEN)Validating Terragrunt configurations...$(NC)"
	@find terragrunt -name "terragrunt.hcl" -exec dirname {} \; | while read dir; do \
		echo "$(YELLOW)Validating $$dir$(NC)"; \
		(cd "$$dir" && terragrunt validate --terragrunt-non-interactive) || exit 1; \
	done
	@echo "$(GREEN)All configurations valid$(NC)"

validate-env: ## Validate specific environment
	@echo "$(GREEN)Validating $(ENVIRONMENT) environment...$(NC)"
	@cd terragrunt/environments/$(ENVIRONMENT) && \
		terragrunt run-all validate --terragrunt-non-interactive
	@echo "$(GREEN)$(ENVIRONMENT) environment valid$(NC)"

fmt-check: ## Check Terraform formatting
	@echo "$(YELLOW)Checking Terraform formatting...$(NC)"
	@terraform fmt -check=true -recursive terraform/
	@echo "$(GREEN)Formatting check passed$(NC)"

fmt-fix: ## Fix Terraform formatting
	@echo "$(YELLOW)Fixing Terraform formatting...$(NC)"
	@terraform fmt -recursive terraform/
	@echo "$(GREEN)Formatting fixed$(NC)"

# ===== SECURITY SCANNING =====

security-scan: ## Run security scans (Checkov, tfsec, Terrascan)
	@echo "$(GREEN)Running security scans...$(NC)"
	@$(MAKE) checkov-scan
	@$(MAKE) tfsec-scan
	@$(MAKE) terrascan-scan
	@echo "$(GREEN)Security scans complete$(NC)"

checkov-scan: ## Run Checkov security scan
	@echo "$(YELLOW)Running Checkov...$(NC)"
	@docker run --rm -v $$(pwd):/tf bridgecrew/checkov \
		-d /tf/terraform --framework terraform \
		--output json > /tmp/checkov-results.json || true
	@cat /tmp/checkov-results.json | jq '.summary'

tfsec-scan: ## Run tfsec security scan
	@echo "$(YELLOW)Running tfsec...$(NC)"
	@docker run --rm -v $$(pwd):/src aquasec/tfsec \
		/src/terraform --format json > /tmp/tfsec-results.json || true
	@cat /tmp/tfsec-results.json | jq '.results | length'

terrascan-scan: ## Run Terrascan compliance scan
	@echo "$(YELLOW)Running Terrascan...$(NC)"
	@docker run --rm -v $$(pwd):/src tenable/terrascan \
		scan -i terraform -t gcp -d /src/terraform \
		-o json > /tmp/terrascan-results.json || true

opa-validate: ## Validate OPA policies
	@echo "$(YELLOW)Validating OPA policies...$(NC)"
	@docker run --rm -v $$(pwd)/atlantis/policies:/policies \
		openpolicyagent/opa test /policies
	@echo "$(GREEN)OPA policies valid$(NC)"

# ===== COST MANAGEMENT =====

cost-estimate: ## Generate cost estimate for environment
	@echo "$(GREEN)Generating cost estimate for $(ENVIRONMENT)...$(NC)"
	@infracost breakdown \
		--path terragrunt/environments/$(ENVIRONMENT) \
		--format table

cost-diff: ## Show cost difference for changes
	@echo "$(GREEN)Calculating cost difference...$(NC)"
	@infracost diff \
		--path terragrunt/environments/$(ENVIRONMENT) \
		--format table

# ===== EVIDENCE COLLECTION =====

evidence-collect: ## Collect evidence for current state
	@echo "$(GREEN)Collecting evidence...$(NC)"
	@mkdir -p /tmp/evidence/$(TIMESTAMP)
	@echo "Evidence collection started: $(TIMESTAMP)" > /tmp/evidence/$(TIMESTAMP)/metadata.txt
	@echo "Environment: $(ENVIRONMENT)" >> /tmp/evidence/$(TIMESTAMP)/metadata.txt
	@echo "Project: $(PROJECT_ID)" >> /tmp/evidence/$(TIMESTAMP)/metadata.txt
	@cd terragrunt/environments/$(ENVIRONMENT) && \
		terragrunt run-all plan --out=/tmp/evidence/$(TIMESTAMP)/plan.tfplan
	@$(MAKE) security-scan
	@cp /tmp/*-results.json /tmp/evidence/$(TIMESTAMP)/
	@find /tmp/evidence/$(TIMESTAMP) -type f -exec sha256sum {} \; > /tmp/evidence/$(TIMESTAMP)/hashes.txt
	@tar czf /tmp/evidence-$(TIMESTAMP).tar.gz -C /tmp/evidence $(TIMESTAMP)
	@echo "$(GREEN)Evidence collected: /tmp/evidence-$(TIMESTAMP).tar.gz$(NC)"

evidence-upload: ## Upload evidence to GCS
	@echo "$(YELLOW)Uploading evidence to GCS...$(NC)"
	@gsutil -h "x-goog-meta-cmmc:CM.L2-3.4.3" \
		-h "x-goog-meta-environment:$(ENVIRONMENT)" \
		-h "x-goog-meta-timestamp:$(TIMESTAMP)" \
		cp /tmp/evidence-$(TIMESTAMP).tar.gz \
		$(EVIDENCE_BUCKET)/manual/$(TIMESTAMP).tar.gz
	@echo "$(GREEN)Evidence uploaded to $(EVIDENCE_BUCKET)/manual/$(TIMESTAMP).tar.gz$(NC)"

evidence-list: ## List recent evidence
	@echo "$(GREEN)Recent evidence files:$(NC)"
	@gsutil ls -l $(EVIDENCE_BUCKET)/manual/ | head -20

# ===== BACKUP & RESTORE =====

backup: ## Backup Atlantis configuration and state
	@echo "$(GREEN)Creating backup...$(NC)"
	@mkdir -p backups
	@tar czf backups/atlantis-backup-$(TIMESTAMP).tar.gz \
		atlantis/*.yaml \
		atlantis/*.yml \
		atlantis/policies/ \
		terragrunt/terragrunt.hcl \
		terragrunt/environments/*/env.hcl
	@echo "$(GREEN)Backup created: backups/atlantis-backup-$(TIMESTAMP).tar.gz$(NC)"

backup-upload: backup ## Backup and upload to GCS
	@echo "$(YELLOW)Uploading backup to GCS...$(NC)"
	@gsutil cp backups/atlantis-backup-$(TIMESTAMP).tar.gz \
		$(EVIDENCE_BUCKET)/backups/
	@echo "$(GREEN)Backup uploaded to GCS$(NC)"

restore: ## Restore from backup
	@echo "$(YELLOW)Available backups:$(NC)"
	@ls -la backups/
	@read -p "Enter backup filename to restore: " BACKUP_FILE; \
		tar xzf backups/$$BACKUP_FILE
	@echo "$(GREEN)Restore complete$(NC)"

# ===== CLEANUP TARGETS =====

clean: ## Clean local temporary files
	@echo "$(YELLOW)Cleaning temporary files...$(NC)"
	@rm -rf /tmp/*-results.json
	@rm -rf /tmp/evidence/
	@rm -rf .terragrunt-cache/
	@find . -type d -name ".terraform" -exec rm -rf {} + 2>/dev/null || true
	@echo "$(GREEN)Cleanup complete$(NC)"

clean-docker: ## Clean Docker resources
	@echo "$(YELLOW)Cleaning Docker resources...$(NC)"
	@cd atlantis && docker-compose down -v
	@docker system prune -f
	@echo "$(GREEN)Docker cleanup complete$(NC)"

# ===== MONITORING TARGETS =====

monitoring-deploy: ## Deploy Prometheus + Grafana monitoring stack
	@echo "$(GREEN)Deploying monitoring stack...$(NC)"
	@chmod +x scripts/setup-monitoring.sh
	@./scripts/setup-monitoring.sh
	@echo "$(GREEN)Monitoring stack deployed$(NC)"

monitoring-build: ## Build custom monitoring exporters
	@echo "$(GREEN)Building monitoring exporters...$(NC)"
	@cd monitoring/exporters && \
		docker build -f Dockerfile.sonarqube -t sonarqube-exporter:latest . && \
		docker build -f Dockerfile.security -t security-scan-exporter:latest . && \
		docker build -f Dockerfile.compliance -t compliance-exporter:latest .
	@echo "$(GREEN)Exporters built successfully$(NC)"

monitoring-start: ## Start monitoring stack
	@echo "$(GREEN)Starting monitoring stack...$(NC)"
	@docker-compose -f monitoring/docker-compose-monitoring.yml up -d
	@echo "$(GREEN)Monitoring stack started$(NC)"

monitoring-stop: ## Stop monitoring stack
	@echo "$(YELLOW)Stopping monitoring stack...$(NC)"
	@docker-compose -f monitoring/docker-compose-monitoring.yml stop
	@echo "$(GREEN)Monitoring stack stopped$(NC)"

monitoring-health: ## Check health of monitoring services
	@echo "$(GREEN)Checking monitoring service health...$(NC)"
	@echo ""
	@echo "Prometheus:    $$(curl -s -o /dev/null -w '%{http_code}' http://localhost:9090/-/healthy)"
	@echo "Grafana:       $$(curl -s -o /dev/null -w '%{http_code}' http://localhost:3000/api/health)"
	@echo "Alertmanager:  $$(curl -s -o /dev/null -w '%{http_code}' http://localhost:9093/-/healthy)"
	@echo ""
	@docker-compose -f monitoring/docker-compose-monitoring.yml ps

monitoring-backup: ## Backup Grafana dashboards and data
	@echo "$(GREEN)Starting Grafana backup...$(NC)"
	@chmod +x scripts/backup-grafana.sh
	@./scripts/backup-grafana.sh
	@echo "$(GREEN)Backup completed$(NC)"

monitoring-alerts: ## List active monitoring alerts
	@echo "$(GREEN)Active Alerts$(NC)"
	@echo "============="
	@curl -s http://localhost:9093/api/v1/alerts | jq -r '.[] | "[\(.labels.severity)] \(.labels.alertname): \(.annotations.summary)"' || echo "No alerts or Alertmanager not running"

monitoring-metrics: ## Show key monitoring metrics
	@echo "$(GREEN)Key Metrics$(NC)"
	@echo "==========="
	@echo "Up Services:        $$(curl -s 'http://localhost:9090/api/v1/query?query=up' | jq '.data.result | length' 2>/dev/null || echo 'N/A')"
	@echo "Active Alerts:      $$(curl -s 'http://localhost:9093/api/v1/alerts' | jq '. | length' 2>/dev/null || echo 'N/A')"
	@echo "Critical Vulns:     $$(curl -s 'http://localhost:9090/api/v1/query?query=security_scan_vulnerability_count{severity="CRITICAL"}' | jq '.data.result[0].value[1] // 0' 2>/dev/null || echo 'N/A')"
	@echo "Compliance Score:   $$(curl -s 'http://localhost:9090/api/v1/query?query=compliance_assessment_readiness_score' | jq '.data.result[0].value[1] // "N/A"' 2>/dev/null || echo 'N/A')%"

monitoring-compliance: ## Generate monitoring compliance report
	@echo "$(GREEN)Generating compliance report...$(NC)"
	@mkdir -p compliance/evidence/reports
	@echo "=== Monitoring Compliance Report ===" > compliance/evidence/reports/monitoring-report-$(TIMESTAMP).txt
	@echo "Generated: $$(date)" >> compliance/evidence/reports/monitoring-report-$(TIMESTAMP).txt
	@echo "" >> compliance/evidence/reports/monitoring-report-$(TIMESTAMP).txt
	@echo "CMMC Control Coverage:" >> compliance/evidence/reports/monitoring-report-$(TIMESTAMP).txt
	@curl -s 'http://localhost:9090/api/v1/query?query=compliance_control_coverage_percent{framework="cmmc"}' | \
		jq -r '.data.result[0].value[1] // "N/A"' >> compliance/evidence/reports/monitoring-report-$(TIMESTAMP).txt 2>/dev/null || echo "N/A" >> compliance/evidence/reports/monitoring-report-$(TIMESTAMP).txt
	@echo "" >> compliance/evidence/reports/monitoring-report-$(TIMESTAMP).txt
	@echo "Evidence collected at: compliance/evidence/reports/monitoring-report-$(TIMESTAMP).txt"

# ===== SECURITY SHORTCUTS =====

security-suite: ## Run full security suite and package evidence
	@$(MAKE) -C security suite

security-infra: ## Infra checks + infra pen tests
	@$(MAKE) -C security infra

security-dast: ## DAST + deployment validation
	@$(MAKE) -C security dast
	@$(MAKE) -C security validate

# ===== DNS SHORTCUTS =====

dns-backup: ## Export live DNS (getHosts) -> evidence + snapshot
	@$(MAKE) -C dns backup

dns-plan: ## Diff: desired.records vs live DNS -> evidence diff
	@$(MAKE) -C dns plan

dns-apply-dry: ## Dry-run Namecheap update
	@$(MAKE) -C dns apply-dry

dns-apply: ## Apply Namecheap update (REPLACES ALL HOSTS) requires CONFIRM_OVERWRITE=1
	@$(MAKE) -C dns apply CONFIRM_OVERWRITE=$(CONFIRM_OVERWRITE)

# Default target
.DEFAULT_GOAL := help
