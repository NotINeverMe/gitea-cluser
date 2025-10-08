# Repository Guidelines

## Project Structure & Module Organization
Infrastructure-as-code lives in `terraform/` (`gitea-stack/` for the stack, `modules/` for reusables, `policies/` for OPA/Sentinel). Environment overlays sit in `terragrunt/` with `_envcommon/` for shared inputs and `environments/{dev,staging,prod}/` for overrides. Operational assets include `atlantis/` (compose + policies), `monitoring/` (Prometheus/Grafana stack), `dashboard/` (Flask UI), and `scripts/` for setup, backup, and evidence tasks. Park fixtures or replay data under `tests/`.

## Build, Test, and Development Commands
Use the Makefile targets as your entry point:
```bash
make setup            # bootstrap Atlantis prerequisites and secrets scaffolding
make start            # launch Atlantis via docker-compose
make validate         # run terragrunt validate across all stacks
make fmt-check        # enforce terraform fmt across terraform/
make security-scan    # execute Checkov, tfsec, and Terrascan
make monitoring-deploy  # stand up the Prometheus/Grafana stack
```
For the dashboard UI, run `docker-compose -f dashboard/docker-compose-dashboard.yml up --build` for an end-to-end check or `python3 app.py` during quick iteration.

## Coding Style & Naming Conventions
Run `terraform fmt`; keep HCL at two-space indentation, snake_case variables, and kebab-case resource names that reflect purpose (e.g., `runner_actions_cache`). Shell scripts use Bash with `set -euo pipefail`, four-space function indents, and uppercase constants. Python inside `dashboard/` should stay PEP 8 compliant with docstrings and modular blueprints rather than monolithic routes.

## Testing Guidelines
Before a PR, run `make validate`, `make security-scan`, and `make fmt-check`, then inspect the `/tmp` JSON reports. Capture `terragrunt run-all plan --terragrunt-non-interactive` output when environment files change. Dashboard updates should be rebuilt with the compose command above, checked at `http://localhost:8000`, and documented with fresh screenshots; stash supporting mocks in `tests/`.

## Commit & Pull Request Guidelines
Follow the history by using a capitalized subject with an optional scope, e.g., `Infrastructure: tighten bucket IAM` or `Dashboard: add compliance tile`. Keep commits focused; include evidence snippets only when essential. PRs should outline intent, list affected environments/modules, link issues, attach terraform/terragrunt plan snippets and security-scan deltas, add UI media where relevant, and flag any manual follow-up.

## Security & Compliance Notes
Never commit secrets; populate `atlantis/.env` templates and local `.tfvars` overrides instead. For compliance-impacting work, run `make evidence-collect` and upload via `make evidence-upload` when policy demands. Map new services to CMMC controls using `CONTROL_MAPPING_MATRIX.md`, and extend OPA guardrails in `atlantis/policies/` as the surface area grows.
