# Repository Guidelines

## Project Structure & Module Organization
- IaC in `terraform/`: `gitea-stack/` (stack), `modules/` (reusables), `policies/` (OPA/Sentinel).
- Environment overlays in `terragrunt/`: `_envcommon/` (shared inputs), `environments/{dev,staging,prod}/` (overrides).
- Ops assets: `atlantis/` (compose + policies), `monitoring/` (Prometheus/Grafana), `dashboard/` (Flask UI), `scripts/` (setup/backup/evidence).
- Tests, fixtures, and replay data in `tests/`.

## Build, Test, and Development Commands
- `make setup` — bootstrap Atlantis prerequisites and secrets scaffolding.
- `make start` — launch Atlantis via docker-compose.
- `make validate` — run `terragrunt validate` across stacks.
- `make fmt-check` — enforce `terraform fmt` in `terraform/`.
- `make security-scan` — run Checkov, tfsec, Terrascan (reports in `/tmp`).
- `make monitoring-deploy` — deploy the Prometheus/Grafana stack.
- Dashboard: `docker-compose -f dashboard/docker-compose-dashboard.yml up --build` (E2E) or `python3 app.py` (iterate).

## Coding Style & Naming Conventions
- HCL: two-space indent; `snake_case` variables; kebab-case resource names reflecting purpose (e.g., `runner_actions_cache`). Always run `terraform fmt`.
- Shell: Bash with `set -euo pipefail`, functions indented 4 spaces, UPPERCASE constants.
- Python (`dashboard/`): PEP 8, docstrings, modular blueprints—not monolithic routes.

## Testing Guidelines
- Before PRs: run `make validate`, `make security-scan`, `make fmt-check`; review `/tmp` JSON outputs.
- When environment files change, capture `terragrunt run-all plan --terragrunt-non-interactive`.
- For dashboard changes, rebuild/run, verify at `http://localhost:8000`, add screenshots; stash mocks in `tests/`.

## Commit & Pull Request Guidelines
- Commits: capitalized subject with optional scope, e.g., `Infrastructure: tighten bucket IAM`, `Dashboard: add compliance tile`. Keep focused; include evidence only when essential.
- PRs: describe intent, list affected environments/modules, link issues, attach plan snippets and security-scan deltas, include UI media, and flag manual follow-up.

## Security & Compliance Notes
- Never commit secrets; use `atlantis/.env` templates and local `.tfvars`.
- For compliance-impacting work: `make evidence-collect` then `make evidence-upload`.
- Map services to CMMC controls via `CONTROL_MAPPING_MATRIX.md`; extend OPA guardrails in `atlantis/policies/` as the surface area grows.

