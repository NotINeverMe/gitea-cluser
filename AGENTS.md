# Repository Guidelines

## Project Structure & Module Organization
Infrastructure-as-code lives in `terraform/` with `gitea-stack/` as the core stack, reusable building blocks in `modules/`, and guardrails under `policies/`. Environment overlays reside in `terragrunt/`: `_envcommon/` holds shared inputs, while `environments/{dev,staging,prod}/` apply overrides per tier. Operational assets are split across `atlantis/` (deployment automation), `monitoring/` (Prometheus/Grafana), `dashboard/` (Flask UI), and `scripts/` (setup, backups, evidence capture). Tests, fixtures, and replay data are consolidated in `tests/`.

## Build, Test, and Development Commands
Run `make setup` to scaffold Atlantis prerequisites and local secrets templates. `make start` spins up Atlantis via Docker Compose for iterative changes. Validate infrastructure with `make validate` (delegates to `terragrunt validate` across stacks) and enforce formatting through `make fmt-check`. Security posture is assessed with `make security-scan`, which aggregates Checkov, tfsec, and Terrascan outputs under `/tmp`. For observability work, `make monitoring-deploy` publishes the Prometheus/Grafana stack. The dashboard can be exercised end-to-end with `docker-compose -f dashboard/docker-compose-dashboard.yml up --build` or run locally via `python3 app.py`.

## Coding Style & Naming Conventions
Terraform and Terragrunt files use two-space indents, `snake_case` variables, and kebab-case resource names describing intent (e.g., `runner_actions_cache`). Always finish with `terraform fmt`. Bash scripts begin with `set -euo pipefail`, keep functions indented 4 spaces, and reserve UPPERCASE for constants. Python under `dashboard/` follows PEP 8, applies docstrings, and prefers modular blueprints instead of monolithic route tables.

## Testing Guidelines
Before opening a PR, run `make validate`, `make fmt-check`, and `make security-scan`, reviewing generated JSON artifacts in `/tmp`. Any Terragrunt environment change requires evidence from `terragrunt run-all plan --terragrunt-non-interactive`. Dashboard updates should be validated manually at `http://localhost:8000`, with screenshots or mock data stored in `tests/`. Add or adjust fixtures when APIs evolve to keep replay runs deterministic.

## Commit & Pull Request Guidelines
Commit subjects stay capitalized and scoped when useful, e.g., `Infrastructure: tighten bucket IAM`. Keep diffs focused and omit sensitive evidence from version control. Pull requests document intent, enumerate impacted environments or modules, link supporting issues, and attach plan snippets plus security-scan deltas. Include UI screenshots for dashboard work and call out any manual follow-up tasks.

## Security & Compliance Notes
Treat secrets as ephemeral: use `atlantis/.env` templates and local `.tfvars`, never committing live credentials. For compliance-impacting work, capture artifacts with `make evidence-collect` and upload via `make evidence-upload`. Reference `CONTROL_MAPPING_MATRIX.md` when mapping services to CMMC controls, and extend guardrails in `atlantis/policies/` as coverage grows.
