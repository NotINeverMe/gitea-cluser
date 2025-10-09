# DNS Subproject: Namecheap Management, Backup, and Evidence

Purpose
- Manage, configure, and back up Namecheap DNS records for DR/IR, compliance, and deployment workflows.
- Provide auditable evidence artifacts and reproducible desired-state definitions.

What’s inside
- Makefile: entry points for backup, plan, apply, and evidence packaging
- scripts/: shell utilities (no external deps beyond curl, diff, sed, awk)
- config/desired.records: simple desired-state list (name type address ttl [mx_pref])
- snapshots/: optional canonical YAML snapshots created from live DNS

Quick start
1) Copy env template and fill values (never commit secrets):
   cp dns/.env.example dns/.env
   # edit dns/.env (NAMECHEAP_* and SLD/TLD)

2) Backup current records (raw XML + summary):
   make -C dns backup

3) Review or define desired state:
   edit dns/config/desired.records

4) See changes (produces a diff evidence file):
   make -C dns plan

5) Apply desired state (danger: replaces ALL host records):
   CONFIRM_OVERWRITE=1 make -C dns apply

Evidence & outputs
- compliance/evidence/dns/: raw XML and plan/apply diffs with timestamps
- dns/snapshots/: YAML snapshots derived from getHosts responses

Desired state format (dns/config/desired.records)
- One record per line: name type address ttl [mx_pref]
- Examples:
  gitea A 203.0.113.10 300
  atlantis CNAME lb.example.net 300
  dashboard CNAME lb.example.net 300
  @ MX smtp.google.com. 1799 1

Notes
- The apply path wraps scripts/dns-update-namecheap.sh and now supports MXPrefN.
- setHosts replaces ALL records for SLD.TLD; ensure the file reflects the full set you want.
- For safer operations, run `make -C dns plan` and `make -C dns apply-dry` first.

