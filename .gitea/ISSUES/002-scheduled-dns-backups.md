Title: DNS: Scheduled backups with evidence and retention

Summary
- Implement regular automated backups of Namecheap DNS records with raw XML artifacts and YAML summaries, stored under `compliance/evidence/dns/` and optionally uploaded to the evidence bucket.

Motivation
- Ensure DR/IR readiness and compliance evidence for DNS state over time.

Scope
- Leverage the new `dns/` subproject:
  - Run `dns/scripts/export.sh` on a schedule (e.g., daily/hourly) to capture `getHosts`.
  - Keep rolling retention locally and optionally package/upload to `${PROJECT_ID}` evidence bucket.
  - Produce SHA256 hashes and a single tarball per run via `dns/scripts/evidence-pack.sh`.
  - Expose a Make target and a simple Dockerized cron job for environments without systemd.

Technical Options
- Option A (local/dev): cron or systemd timer calling `make -C dns backup evidence`.
- Option B (containerized): add a small `dns/backup.Dockerfile` that runs `crond` with the above commands and mounts credentials.
- Option C (CI): configure a Gitea Actions/runner scheduled pipeline to run the commands and stash artifacts.

Acceptance Criteria
- A scheduled mechanism exists that runs at the configured interval and writes new XML/YAML evidence under `compliance/evidence/dns/`.
- Evidence tarballs with hashes appear in `/tmp/dns-evidence-*.tar.gz` or are uploaded to the configured bucket.
- Failures are logged and visible (stdout logs or monitoring scrape target).
- Documentation explains enabling/disabling the schedule and required env vars.

Tasks
- [ ] Add Make target `dns-backup-scheduled` that runs backup + evidence.
- [ ] Provide example cron entry and optional Dockerized cron service.
- [ ] Optional: wire upload step using existing `make evidence-upload` pattern.
- [ ] Add retention guidance (e.g., prune older than N days).
- [ ] Docs update under `dns/README.md` and main `README_ATLANTIS_GITOPS.md`.

References
- `dns/scripts/export.sh`, `dns/scripts/evidence-pack.sh`
- `docs/DNS_ACTION_PLAN_NAMECHEAP.md`

