Title: Infrastructure: DNS automation during deployments (Terragrunt/Atlantis)

Summary
- Integrate DNS record creation/updates into the deployment pipeline so new architecture publishes required A/MX (and future CNAME/TXT) records automatically with evidence capture.

Motivation
- Ensure new services/domains are reachable immediately after deploys while maintaining an auditable trail and guardrails.

Scope
- Post‑apply hook (Atlantis/Terragrunt) calls the `dns/` subproject to plan/apply DNS changes:
  - Read outputs (e.g., LB IP/hostnames) from Terragrunt/Terraform.
  - Populate/refresh `dns/config/desired.records` for the environment.
  - Run `make -C dns plan` for diff evidence.
  - With approval, run `CONFIRM_OVERWRITE=1 make -C dns apply` to update Namecheap.
  - Store evidence artifacts under `compliance/evidence/dns/`.

Guardrails
- Because `setHosts` replaces ALL records, prefer one of:
  1) Manage the entire domain’s host set in code (desired.records is authoritative), or
  2) Delegate a subzone (e.g., `ops.<domain>`) and limit automation to that subzone.
- Alternatively implement merge logic: fetch current hosts, merge only the env‑owned hosts into a complete set, and apply. (Add label/comment markers for ownership, if needed.)

Acceptance Criteria
- A reproducible pipeline step exists (Atlantis workflow or Terragrunt hook) that updates DNS as part of deploys.
- Changes are visible in a plan diff and require explicit confirmation before apply.
- Evidence artifacts are created and include raw XML responses and a summarized diff.
- Environment overlays carry `SLD`, `TLD`, and desired hostnames per env (dev/staging/prod).

Tasks
- [ ] Add Terragrunt/Atlantis post‑apply step to invoke `dns/` make targets with env vars.
- [ ] Map Terraform outputs to desired.records generation (helper script or template).
- [ ] Implement merge strategy or confirm subzone delegation strategy; document chosen approach.
- [ ] Update `docs/DNS_ACTION_PLAN_NAMECHEAP.md` with pipeline wiring instructions.
- [ ] Test end‑to‑end in dev; capture evidence bundle.

References
- `dns/` subproject (plan/apply), `scripts/dns-update-namecheap.sh`
- `docs/DNS_ACTION_PLAN_NAMECHEAP.md`, `atlantis/atlantis.yaml`

