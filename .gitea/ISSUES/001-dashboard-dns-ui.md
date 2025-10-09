Title: Dashboard: Namecheap DNS management UI (A/MX)

Summary
- Build a secure, internal dashboard UI to view and manage Namecheap DNS records. Start with A and MX records, with an extensible design to add CNAME/TXT later. Integrate evidence capture and guardrails around Namecheap setHosts behavior (which replaces all records).

Motivation
- Reduce manual DNS changes, improve auditability (CMMC/NIST), and enable safer, repeatable updates from a controlled UI.

Scope
- Add a Flask blueprint under `dashboard/` to:
  - Display live DNS records for a selected domain via `namecheap.domains.dns.getHosts`.
  - Support CRUD for A and MX records (name, address, TTL, MX pref).
  - Use a read–modify–write flow to build the full host set, then call `setHosts` with confirmation.
  - Persist evidence to `compliance/evidence/dns/` (raw XML + summarized JSON/Markdown) with timestamps and hashes.
  - Use environment-driven config for `SLD`, `TLD`, and Namecheap credentials; no secrets stored in code.
  - RBAC: restrict access to authorized users; add CSRF protection.
  - Dry-run preview of the outgoing curl/fields before applying.

Out of scope (initial)
- Managing advanced Namecheap options beyond core DNS records.
- Multi-tenant domain selection (allow later via config).

Technical Notes
- Reuse `scripts/dns-update-namecheap.sh` semantics (now supports `MXPrefN` and optional `EMAIL_TYPE`).
- Wrap API calls in a small Python helper using `requests` so the UI can pull getHosts and push setHosts.
- Ensure evidence write does not block UI (background thread or async task if needed).
- Follow repo guidelines: docstrings, modular blueprints, PEP 8.

Acceptance Criteria
- UI page lists current A and MX records for `${SLD}.${TLD}` fetched from Namecheap.
- Users can add/update/delete A/MX records; changes show a preview (diff) and require explicit confirmation before applying.
- Applying changes writes raw API XML and a human-readable summary to `compliance/evidence/dns/` with a timestamp; files include SHA256 hashes via existing evidence flow.
- Access requires authentication and proper role/permission; CSRF enabled for forms.
- README updates with screenshots and usage documented in `docs/` and `dashboard` README.

Tasks
- [ ] Create `dashboard/blueprints/dns/` with list/add/edit/delete views.
- [ ] Add `dashboard/services/namecheap.py` helper (getHosts, setHosts, XML parsing).
- [ ] Implement read–modify–write assembler and diff preview.
- [ ] Evidence writer to `compliance/evidence/dns/` (XML + summary + hash).
- [ ] Wire env var config and secret management (no secrets in repo).
- [ ] RBAC + CSRF controls; tests for permission and form validation.
- [ ] Update dashboard navigation and compose file if needed.
- [ ] Docs + screenshots per repo guidelines.

References
- `docs/DNS_ACTION_PLAN_NAMECHEAP.md`
- `scripts/dns-update-namecheap.sh`
- `dns/` subproject (backup/plan/apply)

