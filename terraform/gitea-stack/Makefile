# Makefile for Gitea Stack Terraform Module
# DevSecOps Platform Engineering

SHELL := /bin/bash
.DEFAULT_GOAL := help

# Variables
TF_COMMAND := terraform
STACK_NAME := gitea
DOCKER_COMMAND := docker
TIMESTAMP := $(shell date +%Y%m%d_%H%M%S)

# Colors for output
RED := \033[0;31m
GREEN := \033[0;32m
YELLOW := \033[0;33m
BLUE := \033[0;34m
NC := \033[0m # No Color

# Terraform variables
TF_VARS_FILE := terraform.tfvars
TF_PLAN_FILE := tfplan

# Security scan tools
TFSEC := tfsec
CHECKOV := checkov
TRIVY := trivy

.PHONY: help
help: ## Show this help message
	@echo -e "${GREEN}Gitea Stack Terraform Module - Available Targets${NC}"
	@echo -e "${BLUE}================================================${NC}"
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | awk 'BEGIN {FS = ":.*?## "}; {printf "${YELLOW}%-20s${NC} %s\n", $$1, $$2}'

.PHONY: init
init: ## Initialize Terraform
	@echo -e "${BLUE}[*] Initializing Terraform...${NC}"
	$(TF_COMMAND) init -upgrade
	@echo -e "${GREEN}[✓] Terraform initialized${NC}"

.PHONY: validate
validate: ## Validate Terraform configuration
	@echo -e "${BLUE}[*] Validating Terraform configuration...${NC}"
	$(TF_COMMAND) validate
	$(TF_COMMAND) fmt -check=true -diff
	@echo -e "${GREEN}[✓] Configuration valid${NC}"

.PHONY: format
format: ## Format Terraform files
	@echo -e "${BLUE}[*] Formatting Terraform files...${NC}"
	$(TF_COMMAND) fmt -recursive
	@echo -e "${GREEN}[✓] Files formatted${NC}"

.PHONY: plan
plan: init validate ## Create Terraform plan
	@echo -e "${BLUE}[*] Creating Terraform plan...${NC}"
	@if [ ! -f "$(TF_VARS_FILE)" ]; then \
		echo -e "${YELLOW}[!] Creating terraform.tfvars from example...${NC}"; \
		cp terraform.tfvars.example $(TF_VARS_FILE); \
		echo -e "${RED}[!] Please edit terraform.tfvars before applying${NC}"; \
		exit 1; \
	fi
	$(TF_COMMAND) plan -var-file=$(TF_VARS_FILE) -out=$(TF_PLAN_FILE)
	@echo -e "${GREEN}[✓] Plan created: $(TF_PLAN_FILE)${NC}"

.PHONY: apply
apply: plan ## Apply Terraform configuration
	@echo -e "${BLUE}[*] Applying Terraform configuration...${NC}"
	@echo -e "${YELLOW}[!] This will create resources. Continue? [y/N]${NC}"
	@read -r confirm && [ "$$confirm" = "y" ] || (echo "Aborted" && exit 1)
	$(TF_COMMAND) apply $(TF_PLAN_FILE)
	@rm -f $(TF_PLAN_FILE)
	@echo -e "${GREEN}[✓] Infrastructure deployed${NC}"
	@$(MAKE) show-urls

.PHONY: destroy
destroy: ## Destroy all resources
	@echo -e "${RED}[!] WARNING: This will destroy all resources!${NC}"
	@echo -e "${YELLOW}[!] Are you sure? Type 'destroy' to confirm:${NC}"
	@read -r confirm && [ "$$confirm" = "destroy" ] || (echo "Aborted" && exit 1)
	$(TF_COMMAND) destroy -var-file=$(TF_VARS_FILE) -auto-approve
	@echo -e "${GREEN}[✓] Resources destroyed${NC}"

.PHONY: show
show: ## Show current state
	@echo -e "${BLUE}[*] Current Terraform state:${NC}"
	$(TF_COMMAND) show

.PHONY: output
output: ## Show outputs
	@echo -e "${BLUE}[*] Stack outputs:${NC}"
	$(TF_COMMAND) output

.PHONY: show-urls
show-urls: ## Display service URLs
	@echo -e "${GREEN}=== Service URLs ===${NC}"
	@echo -e "${YELLOW}Gitea:${NC}     $$($(TF_COMMAND) output -raw gitea_url 2>/dev/null || echo 'Not deployed')"
	@echo -e "${YELLOW}Dashboard:${NC} $$($(TF_COMMAND) output -raw dashboard_url 2>/dev/null || echo 'Not deployed')"
	@echo -e "${YELLOW}Admin:${NC}     $$($(TF_COMMAND) output -raw admin_username 2>/dev/null || echo 'Not deployed')"

.PHONY: health
health: ## Check health of deployed services
	@echo -e "${BLUE}[*] Checking service health...${NC}"
	@GITEA_URL=$$($(TF_COMMAND) output -raw gitea_url 2>/dev/null) && \
		if [ ! -z "$$GITEA_URL" ]; then \
			curl -sf "$$GITEA_URL/api/healthz" > /dev/null && \
			echo -e "${GREEN}[✓] Gitea: Healthy${NC}" || \
			echo -e "${RED}[✗] Gitea: Unhealthy${NC}"; \
		fi
	@DASHBOARD_URL=$$($(TF_COMMAND) output -raw dashboard_url 2>/dev/null) && \
		if [ ! -z "$$DASHBOARD_URL" ]; then \
			curl -sf "$$DASHBOARD_URL/health" > /dev/null && \
			echo -e "${GREEN}[✓] Dashboard: Healthy${NC}" || \
			echo -e "${RED}[✗] Dashboard: Unhealthy${NC}"; \
		fi

.PHONY: logs
logs: ## Show container logs
	@echo -e "${BLUE}[*] Showing container logs...${NC}"
	$(DOCKER_COMMAND) ps --filter "label=com.devsecops.stack=$(STACK_NAME)" --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}"
	@echo ""
	@echo -e "${YELLOW}Select container to view logs:${NC}"
	@echo "1) gitea"
	@echo "2) postgres-gitea"
	@echo "3) gitea-runner"
	@echo "4) dashboard-gitea"
	@read -p "Enter choice [1-4]: " choice; \
	case $$choice in \
		1) $(DOCKER_COMMAND) logs --tail 100 -f gitea ;; \
		2) $(DOCKER_COMMAND) logs --tail 100 -f postgres-gitea ;; \
		3) $(DOCKER_COMMAND) logs --tail 100 -f gitea-runner ;; \
		4) $(DOCKER_COMMAND) logs --tail 100 -f dashboard-gitea ;; \
		*) echo "Invalid choice" ;; \
	esac

.PHONY: backup
backup: ## Backup volumes to tar files
	@echo -e "${BLUE}[*] Creating backups...${NC}"
	@mkdir -p backups/$(TIMESTAMP)
	@for volume in gitea_data gitea_config postgres_gitea_data; do \
		echo -e "${YELLOW}[*] Backing up $$volume...${NC}"; \
		$(DOCKER_COMMAND) run --rm -v $$volume:/data -v $$(pwd)/backups/$(TIMESTAMP):/backup alpine \
			tar czf /backup/$$volume.tar.gz /data && \
		echo -e "${GREEN}[✓] $$volume backed up${NC}"; \
	done
	@echo -e "${GREEN}[✓] All backups created in backups/$(TIMESTAMP)${NC}"

.PHONY: restore
restore: ## Restore volumes from backup
	@echo -e "${BLUE}[*] Available backups:${NC}"
	@ls -la backups/
	@read -p "Enter backup timestamp to restore: " timestamp; \
	if [ -d "backups/$$timestamp" ]; then \
		echo -e "${RED}[!] WARNING: This will overwrite current data!${NC}"; \
		read -p "Continue? [y/N]: " confirm; \
		if [ "$$confirm" = "y" ]; then \
			for volume in gitea_data gitea_config postgres_gitea_data; do \
				echo -e "${YELLOW}[*] Restoring $$volume...${NC}"; \
				$(DOCKER_COMMAND) run --rm -v $$volume:/data -v $$(pwd)/backups/$$timestamp:/backup alpine \
					sh -c "rm -rf /data/* && tar xzf /backup/$$volume.tar.gz -C /" && \
				echo -e "${GREEN}[✓] $$volume restored${NC}"; \
			done; \
		fi; \
	else \
		echo -e "${RED}[✗] Backup not found${NC}"; \
	fi

.PHONY: security-scan
security-scan: ## Run security scans on Terraform code
	@echo -e "${BLUE}[*] Running security scans...${NC}"
	@if command -v $(TFSEC) > /dev/null; then \
		echo -e "${YELLOW}[*] Running tfsec...${NC}"; \
		$(TFSEC) . --format json --out tfsec-report-$(TIMESTAMP).json; \
		$(TFSEC) .; \
	else \
		echo -e "${YELLOW}[!] tfsec not installed, skipping${NC}"; \
	fi
	@if command -v $(CHECKOV) > /dev/null; then \
		echo -e "${YELLOW}[*] Running checkov...${NC}"; \
		$(CHECKOV) -d . --output json --output-file checkov-report-$(TIMESTAMP).json; \
		$(CHECKOV) -d . --compact; \
	else \
		echo -e "${YELLOW}[!] checkov not installed, skipping${NC}"; \
	fi
	@echo -e "${GREEN}[✓] Security scans complete${NC}"

.PHONY: container-scan
container-scan: ## Scan Docker images for vulnerabilities
	@echo -e "${BLUE}[*] Scanning container images...${NC}"
	@if command -v $(TRIVY) > /dev/null; then \
		for image in gitea/gitea:1.21-rootless postgres:15-alpine gitea/act_runner:latest caddy:2-alpine; do \
			echo -e "${YELLOW}[*] Scanning $$image...${NC}"; \
			$(TRIVY) image --severity HIGH,CRITICAL $$image; \
		done; \
	else \
		echo -e "${YELLOW}[!] trivy not installed, skipping${NC}"; \
	fi
	@echo -e "${GREEN}[✓] Container scans complete${NC}"

.PHONY: evidence
evidence: ## Generate compliance evidence
	@echo -e "${BLUE}[*] Generating compliance evidence...${NC}"
	@mkdir -p evidence/$(TIMESTAMP)
	@echo "Deployment Evidence Report" > evidence/$(TIMESTAMP)/report.md
	@echo "=========================" >> evidence/$(TIMESTAMP)/report.md
	@echo "" >> evidence/$(TIMESTAMP)/report.md
	@echo "Timestamp: $(TIMESTAMP)" >> evidence/$(TIMESTAMP)/report.md
	@echo "Stack: $(STACK_NAME)" >> evidence/$(TIMESTAMP)/report.md
	@echo "" >> evidence/$(TIMESTAMP)/report.md
	@echo "## Terraform State" >> evidence/$(TIMESTAMP)/report.md
	@$(TF_COMMAND) show -json > evidence/$(TIMESTAMP)/state.json
	@echo "State exported to state.json" >> evidence/$(TIMESTAMP)/report.md
	@echo "" >> evidence/$(TIMESTAMP)/report.md
	@echo "## Container Status" >> evidence/$(TIMESTAMP)/report.md
	@$(DOCKER_COMMAND) ps --filter "label=com.devsecops.stack=$(STACK_NAME)" --format json > evidence/$(TIMESTAMP)/containers.json
	@echo "Container status exported to containers.json" >> evidence/$(TIMESTAMP)/report.md
	@echo "" >> evidence/$(TIMESTAMP)/report.md
	@echo "## Security Configuration" >> evidence/$(TIMESTAMP)/report.md
	@$(TF_COMMAND) output -json security_config > evidence/$(TIMESTAMP)/security.json 2>/dev/null || echo "{}" > evidence/$(TIMESTAMP)/security.json
	@echo "Security configuration exported to security.json" >> evidence/$(TIMESTAMP)/report.md
	@cp deployment_evidence_*.json evidence/$(TIMESTAMP)/ 2>/dev/null || true
	@echo -e "${GREEN}[✓] Evidence generated in evidence/$(TIMESTAMP)${NC}"

.PHONY: test
test: validate security-scan ## Run all tests
	@echo -e "${GREEN}[✓] All tests passed${NC}"

.PHONY: clean
clean: ## Clean temporary files
	@echo -e "${BLUE}[*] Cleaning temporary files...${NC}"
	@rm -f $(TF_PLAN_FILE)
	@rm -f tfsec-report-*.json
	@rm -f checkov-report-*.json
	@rm -f deployment_evidence_*.json
	@echo -e "${GREEN}[✓] Cleanup complete${NC}"

.PHONY: install-tools
install-tools: ## Install required tools
	@echo -e "${BLUE}[*] Installing required tools...${NC}"
	@echo -e "${YELLOW}[*] Installing tfsec...${NC}"
	@curl -s https://raw.githubusercontent.com/aquasecurity/tfsec/master/scripts/install_linux.sh | bash || true
	@echo -e "${YELLOW}[*] Installing checkov...${NC}"
	@pip3 install checkov || true
	@echo -e "${YELLOW}[*] Installing trivy...${NC}"
	@curl -sfL https://raw.githubusercontent.com/aquasecurity/trivy/main/contrib/install.sh | sh -s -- -b /usr/local/bin || true
	@echo -e "${GREEN}[✓] Tool installation complete${NC}"

.PHONY: ssh-setup
ssh-setup: ## Setup SSH key for Git operations
	@echo -e "${BLUE}[*] Setting up SSH key...${NC}"
	@if [ ! -f ~/.ssh/id_ed25519 ]; then \
		ssh-keygen -t ed25519 -C "gitea@$(STACK_NAME)" -f ~/.ssh/id_ed25519 -N ""; \
		echo -e "${GREEN}[✓] SSH key generated${NC}"; \
	else \
		echo -e "${YELLOW}[!] SSH key already exists${NC}"; \
	fi
	@echo -e "${YELLOW}Add this public key to your Gitea account:${NC}"
	@cat ~/.ssh/id_ed25519.pub

.PHONY: quick-start
quick-start: init apply show-urls ## Quick start: init, apply, and show URLs
	@echo -e "${GREEN}[✓] Gitea stack deployed successfully!${NC}"

# CI/CD targets
.PHONY: ci-validate
ci-validate: init validate security-scan ## CI validation pipeline
	@echo -e "${GREEN}[✓] CI validation complete${NC}"

.PHONY: ci-deploy
ci-deploy: init plan ## CI deployment pipeline
	$(TF_COMMAND) apply -auto-approve $(TF_PLAN_FILE)
	@echo -e "${GREEN}[✓] CI deployment complete${NC}"

.PHONY: ci-destroy
ci-destroy: ## CI destroy pipeline
	$(TF_COMMAND) destroy -auto-approve
	@echo -e "${GREEN}[✓] CI destroy complete${NC}"