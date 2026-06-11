---
skill: ci-status
trigger: /ci-status
persona: maestro
version: 1.0.0
plugin: ci-status
---

# CI Status Check

Check the current CI/CD pipeline status and report results.

---

## Procedure

### 1. Detect CI Provider

Check CLAUDE.md for `ci-status.provider` setting. If not set, auto-detect:
- `.github/workflows/` exists → `github-actions`
- `.gitlab-ci.yml` exists → `gitlab-ci`
- `.circleci/` exists → `circleci`

If no CI detected, report: "No CI/CD pipeline detected in this project."

### 2. Fetch Latest Run

**GitHub Actions:**
```bash
gh run list --limit 5 --json status,conclusion,name,createdAt,headBranch
```

**GitLab CI:**
```bash
# Requires glab CLI
glab ci list --per-page 5
```

### 3. Report Status

```
CI Status Report:
- Provider: {provider}
- Latest run: {name} ({branch})
- Status: ✅ success | ❌ failure | 🔄 in_progress
- Time: {createdAt}

{if failure:}
Failed jobs:
- {job_name}: {error_summary}

Suggested fix: {suggestion based on error pattern}
```

### 4. Log Audit Event

Log as audit event with type `CI_CHECK`:
```markdown
---
type: audit
event: CI_CHECK
timestamp: {now}
actor: maestro
data:
  provider: {provider}
  status: {status}
  branch: {branch}
---
```

### 5. Common Failure Patterns

| Error Pattern | Suggestion |
|--------------|------------|
| `npm test` failed | Check test output, run `/investigate` on failing tests |
| `npm run build` failed | Check TypeScript errors, likely type mismatch |
| `lint` failed | Run linter locally, fix before pushing |
| `docker build` failed | Check Dockerfile, missing dependencies |
| Timeout | Check for infinite loops or resource-heavy tests |

---

## Output

Present results to user. If CI is failing, offer to:
1. Show full error logs
2. Run `/investigate` on the failure
3. Acionar o fluxo /fix para root cause analysis
