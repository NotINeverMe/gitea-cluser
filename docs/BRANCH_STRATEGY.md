# Branch Strategy - DCG Gitea Platform

## Overview

This repository follows a **three-tier branch strategy** designed to ensure code quality, enable proper testing, and maintain CMMC 2.0 Level 2 compliance for production deployments.

## Branch Structure

```
dev → staging → main
```

### 1. `dev` - Development Branch

**Purpose**: Active development and feature integration

**Workflow**:
- Feature branches merge into `dev`
- Continuous integration and unit tests run on every commit
- Local testing and development validation
- Fast-paced iteration and collaboration

**Environment**: Local development (no GCP project)

**Merge Policy**:
- Any team member can merge feature branches to `dev`
- No PR required for `dev` (team discretion)
- Must pass CI checks

### 2. `staging` - Staging/Pre-Production Branch

**Purpose**: Integration testing and production validation

**Workflow**:
- Code flows from `dev` to `staging` for final validation
- Deployed to **dcg-gitea-stage** GCP environment
- Full end-to-end testing with production-like configuration
- Security scanning and compliance validation
- Performance testing under load

**Environment**: `dcg-gitea-stage` (GCP project)
- Instance: e2-standard-4
- Domain: `git-stage.dcg.cui-secure.us`
- Full security stack (Cloud Armor, KMS, IAP)

**Merge Policy**:
- Merge from `dev` via PR (recommended) or direct merge
- Must pass all CI/CD checks
- Should be tested in staging environment before promoting to production

### 3. `main` - Production Branch

**Purpose**: Production-ready code only

**Workflow**:
- **ONLY accepts PRs from `staging`** (enforced via GitHub Actions)
- Represents production-ready, validated code
- Every commit to `main` should be deployable to production
- Protected branch with required reviews

**Environment**: `dcg-gitea-prod` (GCP project) - to be deployed
- Instance: e2-standard-4 (cost-optimized)
- Domain: `git.dcg.cui-secure.us`
- Full CMMC 2.0 Level 2 compliance
- Cross-region DR enabled

**Merge Policy** (ENFORCED):
- ✅ **ONLY** PRs from `staging` → `main` allowed
- ❌ Direct pushes blocked
- ❌ PRs from `dev` or feature branches rejected
- Requires passing status checks
- Branch protection enabled

## Branch Protection Rules

### `main` Branch Protection

Configured via GitHub API and enforced by `.github/workflows/enforce-branch-strategy.yml`:

- **Require pull request reviews**: Enabled (0 approvals required for now)
- **Dismiss stale reviews**: Enabled
- **Restrict source branch**: `staging` only (enforced via GitHub Action)
- **Prevent force pushes**: Enabled
- **Prevent branch deletion**: Enabled
- **Status checks**: Required (CI must pass)

## Development Workflows

### Feature Development Workflow

```bash
# 1. Create feature branch from dev
git checkout dev
git pull origin dev
git checkout -b feature/my-feature

# 2. Develop and commit
git add .
git commit -m "feat: Add my feature"

# 3. Push and create PR to dev (optional)
git push origin feature/my-feature
gh pr create --base dev --head feature/my-feature

# 4. Merge to dev (after review or directly)
git checkout dev
git merge feature/my-feature
git push origin dev
```

### Staging Promotion Workflow

```bash
# 1. Ensure dev is stable
git checkout dev
git pull origin dev

# 2. Merge dev to staging
git checkout staging
git pull origin staging
git merge dev

# 3. Push to staging and test
git push origin staging

# 4. Deploy to dcg-gitea-stage and validate
# - Test all functionality
# - Run security scans
# - Verify compliance controls
# - Load testing (if applicable)
```

### Production Promotion Workflow

```bash
# 1. Ensure staging is validated
# - All tests pass
# - Security scans clean
# - Manual QA complete

# 2. Create PR from staging to main
git checkout staging
git pull origin staging
gh pr create --base main --head staging \
  --title "Production Release: [version/date]" \
  --body "Promoting validated changes from staging to production..."

# 3. Wait for GitHub Action validation
# - enforce-branch-strategy.yml verifies source is 'staging'
# - CI/CD checks must pass

# 4. Review and merge PR
# - Review changes in GitHub UI
# - Ensure all checks pass
# - Merge PR (creates commit in main)

# 5. Deploy to dcg-gitea-prod
# - Follow deployment runbook (Issue #21)
# - Post-deployment validation
# - Monitor for issues
```

## Enforcement

### GitHub Actions

**Workflow**: `.github/workflows/enforce-branch-strategy.yml`

**Triggers**: On PR to `main`

**Behavior**:
- ✅ Allows PRs from `staging` → `main`
- ❌ Rejects PRs from any other branch
- 📝 Posts helpful comment with instructions on rejected PRs

### Manual Override (Emergency Only)

In extreme emergencies (security hotfix, critical production bug):

1. **Document the reason** in GitHub issue
2. **Get approval** from platform lead
3. **Disable branch protection temporarily**:
   ```bash
   gh api -X DELETE repos/NotINeverMe/gitea-cluser/branches/main/protection
   ```
4. **Push critical fix**
5. **Re-enable protection immediately**
6. **Post-mortem**: Document why normal process was bypassed

## Environment Mapping

| Branch    | Environment       | GCP Project       | Purpose                  | Instance Type  |
|-----------|-------------------|-------------------|--------------------------|----------------|
| `dev`     | Local             | None              | Development              | N/A            |
| `staging` | Staging           | `dcg-gitea-stage` | Pre-production testing   | e2-standard-4  |
| `main`    | Production        | `dcg-gitea-prod`  | Production workloads     | e2-standard-4  |

## Compliance Considerations

### CMMC 2.0 Level 2 Requirements

**CM.L2-3.4.2** - Baseline Configurations:
- `main` branch represents production baseline
- All changes must flow through `staging` for validation
- Configuration drift is prevented via branch protection

**SI.L2-3.14.1** - Flaw Remediation:
- Security fixes follow same workflow (dev → staging → main)
- Staging validates fixes before production deployment
- Evidence of testing captured in PR reviews

**CP.L2-3.11.1** - Information Backup:
- Git history provides version control and rollback capability
- Protected `main` branch ensures production history integrity

## FAQ

### Q: Why can't I push directly to `main`?

**A**: Direct pushes bypass validation and testing. All production changes must be validated in staging first to ensure quality and compliance.

### Q: What if I have an urgent hotfix?

**A**:
1. Develop fix in `dev`
2. Merge to `staging` and test (even if briefly)
3. Create PR `staging` → `main`
4. Expedite review process

For true emergencies, follow the manual override process documented above.

### Q: Can I create a PR from a feature branch to `main`?

**A**: No. GitHub Actions will reject the PR automatically. You must merge to `staging` first.

### Q: How do I know which branch I'm on?

**A**:
```bash
git branch --show-current
```

### Q: What happens if I try to bypass the rules?

**A**: The GitHub Action workflow will:
- Block the PR merge
- Post a comment with instructions
- Require you to close the PR and follow proper workflow

## References

- **Branch Protection Configuration**: `.github/workflows/enforce-branch-strategy.yml`
- **Deployment Guide**: `docs/GCP_DEPLOYMENT_GUIDE.md`
- **Operations Runbook**: `docs/GCP_OPERATIONS_RUNBOOK.md`
- **GitHub Issues**:
  - [#21: Deploy dcg-gitea-prod](https://github.com/NotINeverMe/gitea-cluser/issues/21)
  - [#22: Fix staging DNS](https://github.com/NotINeverMe/gitea-cluser/issues/22)

## Changelog

- **2025-10-17**: Initial branch strategy implementation
  - Configured branch protection for `main`
  - Added GitHub Action to enforce `staging` → `main` workflow
  - Documented three-tier strategy (dev → staging → main)
