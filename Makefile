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
	@echo "Safety validation:"
	@echo "  $(GREEN)validate-project$(NC)      Validate GCP project and terraform context"
	@echo "  $(GREEN)validate-destroy$(NC)      Validate destroy plan (requires VAR_FILE=...)"
	@echo "  $(GREEN)show-environment$(NC)      Display current environment configuration"
	@echo "  $(GREEN)verify-project$(NC)        Verify GCP project matches Makefile"
	@echo "  $(GREEN)destroy-with-validation$(NC) Safe destroy with multi-layer validation"
	@echo "  $(GREEN)safe-destroy$(NC)          Legacy alias to destroy-with-validation"
	@echo "  $(GREEN)switch-environment$(NC)    Switch environment (requires ENV=dev|staging|prod)"
	@echo "  $(GREEN)switch-env$(NC)            Legacy alias for switch-environment"
	@echo "  $(GREEN)audit-log$(NC)             Show recent environment operations"
	@echo "  $(GREEN)audit-stats$(NC)           Show audit log statistics"
	@echo "  $(GREEN)safety-check$(NC)          Run all safety validation checks"
	@echo "  $(GREEN)pre-flight-check$(NC)      Complete pre-flight checklist"
	@echo "  $(GREEN)emergency-rollback$(NC)    Emergency rollback procedures (interactive)"
	@echo ""
	@echo "Security shortcuts:"
	@echo "  $(GREEN)security-suite$(NC)        Run full app+infra security suite (evidence)"
	@echo "  $(GREEN)security-infra$(NC)        Run infra checks + pen tests"
	@echo "  $(GREEN)security-dast$(NC)         Run ZAP + Nuclei + validation"
	@echo ""
	@echo "DNS shortcuts:"
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

# ===== SAFETY VALIDATION TARGETS =====

validate-project: ## Validate GCP project and terraform context
	@echo "$(GREEN)Running project validation...$(NC)"
	@VAR_FLAG=""; \
	if [ -n "$(VAR_FILE)" ]; then \
	  VAR_FLAG="--var-file=$(VAR_FILE)"; \
	  echo "Using variable file: $(VAR_FILE)"; \
	fi; \
	./scripts/terraform-project-validator.sh \
		--operation=plan \
		--project=$(PROJECT_ID) \
		--terraform-dir=terraform/gcp-gitea \
		$$VAR_FLAG
	@echo "$(GREEN)Project validation complete$(NC)"

validate-destroy: ## Validate destroy plan with safety checks
	@echo "$(GREEN)Running pre-destroy validation...$(NC)"
	@test -n "$(VAR_FILE)" || (echo "$(RED)ERROR: VAR_FILE is required. Use: make validate-destroy VAR_FILE=terraform.tfvars.prod$(NC)" && exit 1)
	@./scripts/pre-destroy-validator.sh \
		--project=$(PROJECT_ID) \
		--var-file=$(VAR_FILE) \
		--terraform-dir=terraform/gcp-gitea
	@echo "$(GREEN)Pre-destroy validation complete$(NC)"

show-environment: ## Display current environment configuration
	@echo "$(GREEN)Current Environment Configuration$(NC)"
	@echo "=================================="
	@echo "GCloud Active Project:   $$(gcloud config get-value project 2>/dev/null || echo 'NOT SET')"
	@echo "Makefile PROJECT_ID:     $(PROJECT_ID)"
	@echo "Makefile ENVIRONMENT:    $(ENVIRONMENT)"
	@echo ""
	@echo "Terraform State:"
	@test -f terraform/gcp-gitea/terraform.tfstate && echo "  State file exists: YES" || echo "  State file exists: NO"
	@test -f terraform/gcp-gitea/terraform.tfvars && echo "  terraform.tfvars: EXISTS (auto-loaded - DANGER)" || echo "  terraform.tfvars: Not found"
	@test -f terraform/gcp-gitea/terraform.tfvars.$(ENVIRONMENT) && echo "  terraform.tfvars.$(ENVIRONMENT): EXISTS" || echo "  terraform.tfvars.$(ENVIRONMENT): Not found"
	@echo ""
	@echo "Safety Scripts:"
	@test -x scripts/terraform-project-validator.sh && echo "  ✓ terraform-project-validator.sh" || echo "  ✗ terraform-project-validator.sh (missing or not executable)"
	@test -x scripts/pre-destroy-validator.sh && echo "  ✓ pre-destroy-validator.sh" || echo "  ✗ pre-destroy-validator.sh (missing or not executable)"
	@test -x scripts/gcp-destroy.sh && echo "  ✓ gcp-destroy.sh" || echo "  ✗ gcp-destroy.sh (missing or not executable)"
	@echo ""
	@test -f docs/SAFE_OPERATIONS_GUIDE.md && echo "Documentation: docs/SAFE_OPERATIONS_GUIDE.md" || echo "$(YELLOW)WARNING: docs/SAFE_OPERATIONS_GUIDE.md not found$(NC)"

verify-project: ## Verify GCP project context matches Makefile
	@echo "$(GREEN)Verifying project context...$(NC)"
	@GCLOUD_PROJECT=$$(gcloud config get-value project 2>/dev/null); \
	if [ -z "$$GCLOUD_PROJECT" ]; then \
		echo "$(RED)ERROR: No active GCP project in gcloud config$(NC)"; \
		echo "$(YELLOW)Run: gcloud config set project $(PROJECT_ID)$(NC)"; \
		exit 1; \
	elif [ "$$GCLOUD_PROJECT" != "$(PROJECT_ID)" ]; then \
		echo "$(RED)ERROR: Project mismatch!$(NC)"; \
		echo "  gcloud active project: $$GCLOUD_PROJECT"; \
		echo "  Makefile PROJECT_ID:   $(PROJECT_ID)"; \
		echo "$(YELLOW)Run: gcloud config set project $(PROJECT_ID)$(NC)"; \
		exit 1; \
	else \
		echo "$(GREEN)✓ Project verified: $(PROJECT_ID)$(NC)"; \
	fi

destroy-with-validation: ## Safe destroy with validation (requires PROJECT_ID, ENVIRONMENT, VAR_FILE)
	@echo "$(RED)╔══════════════════════════════════════════════════════════════════╗$(NC)"
	@echo "$(RED)║              SAFE INFRASTRUCTURE DESTRUCTION                     ║$(NC)"
	@echo "$(RED)╚══════════════════════════════════════════════════════════════════╝$(NC)"
	@echo ""
	@test -n "$(PROJECT_ID)" || (echo "$(RED)ERROR: PROJECT_ID is required$(NC)" && exit 1)
	@test -n "$(ENVIRONMENT)" || (echo "$(RED)ERROR: ENVIRONMENT is required$(NC)" && exit 1)
	@test -n "$(VAR_FILE)" || (echo "$(RED)ERROR: VAR_FILE is required$(NC)" && exit 1)
	@echo "Project:    $(PROJECT_ID)"
	@echo "Environment: $(ENVIRONMENT)"
	@echo "Var file:  $(VAR_FILE)"
	@echo ""
	@$(MAKE) verify-project PROJECT_ID=$(PROJECT_ID)
	@EXPECTED_VALIDATION_FLAG=""; \
	if [ -n "$(EXPECTED_COUNT)" ]; then \
	  EXPECTED_VALIDATION_FLAG="--expected-resources=$(EXPECTED_COUNT)"; \
	  echo "Expected resource count: $(EXPECTED_COUNT)"; \
	fi; \
	./scripts/pre-destroy-validator.sh \
		--project=$(PROJECT_ID) \
		--var-file=$(VAR_FILE) \
		--terraform-dir=terraform/gcp-gitea \
		$$EXPECTED_VALIDATION_FLAG
	@DESTROY_EXPECTED_FLAG=""; \
	if [ -n "$(EXPECTED_COUNT)" ]; then \
	  DESTROY_EXPECTED_FLAG="--expected-count=$(EXPECTED_COUNT)"; \
	fi; \
	./scripts/gcp-destroy.sh \
		-p $(PROJECT_ID) \
		-e $(ENVIRONMENT) \
		-V $(VAR_FILE) \
		-k -b \
		--confirm-project=$(PROJECT_ID) \
		$$DESTROY_EXPECTED_FLAG
	@echo "$(GREEN)Safe destruction complete$(NC)"

safe-destroy: ## Safe destruction with all validations (requires ENVIRONMENT and VAR_FILE)
	@$(MAKE) destroy-with-validation PROJECT_ID=$(PROJECT_ID) ENVIRONMENT=$(ENVIRONMENT) VAR_FILE=$(VAR_FILE) EXPECTED_COUNT=$(EXPECTED_COUNT)

switch-environment: ## Switch environment safely (requires ENV=dev|staging|prod)
	@echo "$(GREEN)Switching to environment: $(ENV)$(NC)"
	@test -n "$(ENV)" || (echo "$(RED)ERROR: ENV is required. Use: make switch-environment ENV=dev$(NC)" && exit 1)
	@test "$(ENV)" = "dev" -o "$(ENV)" = "staging" -o "$(ENV)" = "prod" || \
		(echo "$(RED)ERROR: ENV must be dev, staging, or prod$(NC)" && exit 1)
	@./scripts/environment-selector.sh -e $(ENV)
	@echo "$(GREEN)Environment switched to: $(ENV)$(NC)"
	@echo ""
	@$(MAKE) show-environment

switch-env: ## Legacy alias for switch-environment
	@$(MAKE) switch-environment ENV=$(ENV)

audit-log: ## Show recent environment operations
	@echo "$(GREEN)Recent Environment Operations$(NC)"
	@echo "=============================="
	@echo ""
	@test -f logs/environment-audit.log && ./scripts/audit-report.sh --last 20 || \
		echo "$(YELLOW)No audit log found. Operations will be logged here.$(NC)"

audit-stats: ## Show audit log statistics
	@echo "$(GREEN)Audit Log Statistics$(NC)"
	@echo "===================="
	@echo ""
	@test -f logs/environment-audit.log && ./scripts/audit-report.sh --stats || \
		echo "$(YELLOW)No audit log found.$(NC)"

safety-check: ## Run all safety validation checks
	@echo "$(GREEN)Running comprehensive safety checks...$(NC)"
	@echo ""
	@$(MAKE) show-environment
	@echo ""
	@$(MAKE) verify-project
	@echo ""
	@echo "$(GREEN)Checking git hooks...$(NC)"
	@test -x .git/hooks/pre-commit && echo "  ✓ pre-commit hook installed" || echo "  $(RED)✗ pre-commit hook missing$(NC)"
	@test -x .git/hooks/pre-push && echo "  ✓ pre-push hook installed" || echo "  $(RED)✗ pre-push hook missing$(NC)"
	@echo ""
	@echo "$(GREEN)Checking documentation...$(NC)"
	@test -f docs/SAFE_OPERATIONS_GUIDE.md && echo "  ✓ SAFE_OPERATIONS_GUIDE.md" || echo "  $(RED)✗ Missing safety guide$(NC)"
	@test -f docs/ENVIRONMENT_MANAGEMENT.md && echo "  ✓ ENVIRONMENT_MANAGEMENT.md" || echo "  $(RED)✗ Missing environment guide$(NC)"
	@test -f docs/SAFETY_TRAINING.md && echo "  ✓ SAFETY_TRAINING.md" || echo "  $(RED)✗ Missing training guide$(NC)"
	@echo ""
	@echo "$(GREEN)Checking environment files...$(NC)"
	@test -f terraform/gcp-gitea/.env.dev && echo "  ✓ terraform/gcp-gitea/.env.dev" || echo "  $(YELLOW)⚠ terraform/gcp-gitea/.env.dev not found$(NC)"
	@test -f terraform/gcp-gitea/.env.staging && echo "  ✓ terraform/gcp-gitea/.env.staging" || echo "  $(YELLOW)⚠ terraform/gcp-gitea/.env.staging not found$(NC)"
	@test -f terraform/gcp-gitea/.env.prod && echo "  ✓ terraform/gcp-gitea/.env.prod" || echo "  $(YELLOW)⚠ terraform/gcp-gitea/.env.prod not found$(NC)"
	@echo ""
	@echo "$(GREEN)✅ Safety check complete$(NC)"

pre-flight-check: ## Complete pre-flight checklist (requires PROJECT_ID, ENVIRONMENT, VAR_FILE)
	@echo "$(BLUE)╔══════════════════════════════════════════════════════════════════╗$(NC)"
	@echo "$(BLUE)║                    PRE-FLIGHT CHECKLIST                          ║$(NC)"
	@echo "$(BLUE)╚══════════════════════════════════════════════════════════════════╝$(NC)"
	@echo ""
	@test -n "$(PROJECT_ID)" || (echo "$(RED)ERROR: PROJECT_ID is required$(NC)" && exit 1)
	@test -n "$(ENVIRONMENT)" || (echo "$(RED)ERROR: ENVIRONMENT is required$(NC)" && exit 1)
	@test -n "$(VAR_FILE)" || (echo "$(RED)ERROR: VAR_FILE is required$(NC)" && exit 1)
	@echo "Project:     $(PROJECT_ID)"
	@echo "Environment: $(ENVIRONMENT)"
	@echo "Var file:    $(VAR_FILE)"
	@echo ""
	@echo "$(YELLOW)Running pre-flight checks...$(NC)"
	@echo ""
	@echo "1. Verify gcloud project matches Makefile"
	@$(MAKE) verify-project PROJECT_ID=$(PROJECT_ID)
	@echo ""
	@echo "2. Display current environment configuration"
	@$(MAKE) show-environment ENVIRONMENT=$(ENVIRONMENT)
	@echo ""
	@echo "3. Run Terraform project validator (plan mode)"
	@./scripts/terraform-project-validator.sh \
		--operation=plan \
		--project=$(PROJECT_ID) \
		--terraform-dir=terraform/gcp-gitea \
		--var-file=$(VAR_FILE)
	@echo ""
	@echo "$(GREEN)✅ Pre-flight checklist complete$(NC)"
	@echo ""
	@echo "$(CYAN)You are cleared for deployment!$(NC)"

emergency-rollback: ## Emergency rollback procedures (interactive)
	@echo "$(RED)╔══════════════════════════════════════════════════════════════════╗$(NC)"
	@echo "$(RED)║                    EMERGENCY ROLLBACK                            ║$(NC)"
	@echo "$(RED)╚══════════════════════════════════════════════════════════════════╝$(NC)"
	@echo ""
	@echo "$(YELLOW)This will guide you through emergency rollback procedures.$(NC)"
	@echo ""
	@echo "Available rollback options:"
	@echo "  1. Restore from latest backup (if available)"
	@echo "  2. View disaster recovery procedures"
	@echo "  3. Check recent audit log for incident timeline"
	@echo "  4. View state backup locations"
	@echo ""
	@read -p "Select option (1-4) or 'q' to quit: " option; \
	case $$option in \
		1) \
			echo "$(GREEN)Locating latest backup...$(NC)"; \
			test -x scripts/gcp-restore.sh && ./scripts/gcp-restore.sh || \
				echo "$(RED)Restore script not found. See docs/GCP_DISASTER_RECOVERY.md$(NC)"; \
			;; \
		2) \
			echo "$(GREEN)Opening disaster recovery guide...$(NC)"; \
			test -f docs/GCP_DISASTER_RECOVERY.md && less docs/GCP_DISASTER_RECOVERY.md || \
				echo "$(RED)Disaster recovery guide not found$(NC)"; \
			;; \
		3) \
			echo "$(GREEN)Recent operations (last 50):$(NC)"; \
			echo ""; \
			test -f logs/environment-audit.log && ./scripts/audit-report.sh --last 50 || \
				echo "$(YELLOW)No audit log found$(NC)"; \
			;; \
		4) \
			echo "$(GREEN)State backup locations:$(NC)"; \
			echo ""; \
			echo "Local backups:"; \
			ls -lh .evidence/pre-destroy/terraform-state-backup-*.json 2>/dev/null || echo "  No local backups found"; \
			echo ""; \
			echo "GCS backups:"; \
			gsutil ls gs://$(PROJECT_ID)-gitea-tfstate-*/backups/ 2>/dev/null || echo "  No GCS backups found"; \
			;; \
		q) \
			echo "$(YELLOW)Emergency rollback cancelled$(NC)"; \
			;; \
		*) \
			echo "$(RED)Invalid option$(NC)"; \
			;; \
	esac

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
