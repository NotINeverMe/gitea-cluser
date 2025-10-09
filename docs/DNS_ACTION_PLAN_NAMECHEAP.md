# DNS Action Plan: Subdomains and Namecheap Automation

This action doc locks down the subdomain scheme for the Gitea stack and outlines a safe, auditable way to automate DNS record updates via Namecheap.

## Subdomain Scheme

- Primary services
  - `gitea.cui-secure.us` – primary UI/API
  - `atlantis.cui-secure.us` – automation (Atlantis)
  - `dashboard.cui-secure.us` – monitoring UI (Prometheus/Grafana proxy)
- Multi-environment pattern
  - `dev-gitea.cui-secure.us`, `staging-gitea.cui-secure.us`, `prod-gitea.cui-secure.us`
  - Same prefixing for `atlantis` and `dashboard` if exposed per env
- ACME challenges
  - Reserve `_acme-challenge.<host>.cui-secure.us` records for TLS automation

Notes
- Keep names purpose-specific so auditors recognize endpoints at a glance.
- Use environment prefixes to simplify firewall rules and per-env access control.

## Automation Options

1) Namecheap API (recommended if you stay on Namecheap DNS)
   - Enable API in Namecheap (Account → Tools → Namecheap API) and whitelist your runner/NAT IP.
   - Use `namecheap.domains.dns.getHosts` to read the full host list and `namecheap.domains.dns.setHosts` to write it back with your updates.
   - Important: `setHosts` replaces all host records for the domain; always include the entire desired set.

2) Dynamic DNS (single-host A records)
   - If you only need to update an A record dynamically (e.g., single LB IP), Namecheap Dynamic DNS can be enabled per host and updated with the DDNS endpoint.

3) Delegate a subzone to Cloudflare/Route53
   - Delegate `ops.cui-secure.us` (or similar) to a provider with richer Terraform support and token-based auth, then manage DNS via Terraform.

## Secrets and Environment

Store these as CI/runner secrets (never commit):
- `NAMECHEAP_API_USER`
- `NAMECHEAP_API_KEY`
- `NAMECHEAP_API_IP` (the public IP Namecheap whitelists)

Per-domain inputs:
- `SLD=cui-secure`
- `TLD=us`

Per-record inputs (example):
- `HOSTNAME=gitea`
- `RECORD_TYPE=A` (or `CNAME`)
- `ADDRESS=<current load balancer IP or hostname>`
- `TTL=300` (typical)

## Minimal API Example (single host)

Warning: This overwrites all host records for the domain. Use only when you intentionally manage the full set or in a delegated subzone.

```sh
curl "https://api.namecheap.com/xml.response" \
  --data-urlencode "ApiUser=${NAMECHEAP_API_USER}" \
  --data-urlencode "ApiKey=${NAMECHEAP_API_KEY}" \
  --data-urlencode "UserName=${NAMECHEAP_API_USER}" \
  --data-urlencode "ClientIp=${NAMECHEAP_API_IP}" \
  --data-urlencode "Command=namecheap.domains.dns.setHosts" \
  --data-urlencode "SLD=cui-secure" \
  --data-urlencode "TLD=us" \
  --data-urlencode "HostName1=gitea" \
  --data-urlencode "RecordType1=A" \
  --data-urlencode "Address1=${NEW_IP}" \
  --data-urlencode "TTL1=300"
```

## Safer Workflow (read–modify–write)

To avoid clobbering unrelated records, first fetch current records, then merge your changes, and finally write back the full set. A starter Bash script is provided at `scripts/dns-update-namecheap.sh` that:
- Refuses to run unless `CONFIRM_OVERWRITE=1` is set (defensive default)
- Supports passing multiple records (HostNameN/RecordTypeN/AddressN/TTLN)
- Writes the API response to `/tmp` for evidence

Usage examples are embedded in the script header.

## CI/Make Integration

Add a post-apply step (e.g., Atlantis workflow or Make) that calls the script once Terraform outputs the current LB address. Suggested Make target snippet:

```make
dns-update: ## Update Namecheap DNS hosts (danger: replace all hosts)
	@CONFIRM_OVERWRITE=1 \
	SLD=cui-secure TLD=us TTL=300 \
	NAMECHEAP_API_USER=$$NAMECHEAP_API_USER \
	NAMECHEAP_API_KEY=$$NAMECHEAP_API_KEY \
	NAMECHEAP_API_IP=$$NAMECHEAP_API_IP \
	./scripts/dns-update-namecheap.sh \
	  HostName1=gitea RecordType1=A Address1=$$(terragrunt output -raw lb_ip) \
	  HostName2=atlantis RecordType2=CNAME Address2=$$(terragrunt output -raw atlantis_dns_target) \
	  HostName3=dashboard RecordType3=CNAME Address3=$$(terragrunt output -raw dashboard_dns_target)
```

Note: Adjust outputs to match your stack. Keep the full host list in code to make updates repeatable and auditable.

## DNS Subproject Shortcuts

The `dns/` subproject provides simple Make targets:
- `make dns-backup` — export live DNS (XML evidence + YAML snapshot)
- `make dns-plan` — diff desired vs live DNS; writes evidence diff
- `make dns-apply-dry` — dry-run the setHosts call (no API write)
- `CONFIRM_OVERWRITE=1 make dns-apply` — apply desired state (replaces ALL hosts)

Configure `dns/.env` from `dns/.env.example` with `NAMECHEAP_*`, `SLD`, and `TLD`.

## Evidence

- The script stores the raw XML response to `/tmp/namecheap-dns-YYYYmmdd-HHMMSS.xml`.
- Include this file in `make evidence-collect` bundles if DNS is compliance-impacting for a change.

## Next Steps

1. Confirm final subdomain map (dev/staging/prod) and set `gitea_domain`/root URLs in environment overlays.
2. Enable Namecheap API, whitelist runner IP, and load secrets.
3. Wire a post-apply step to call the update script with the complete host list (or move DNS to a Terraform-friendly provider by delegating a subzone).
