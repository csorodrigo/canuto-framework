---
skill: codex-security-gate
trigger: /security-gate, or automatically before merge on security-sensitive changes
persona: maestro
version: 1.0.0
lastUpdated: 2026-03-30
shortDescription: >
  Security scan via the reviewer path before merge. OWASP Top 10, injection detection, auth bypass,
  race conditions, secrets leakage. Gate that blocks merge if critical issues found.
usedBy: [maestro, cso]
evals:
  - prompt: "run a security scan on this diff"
    should_trigger: true
  - prompt: "check for vulnerabilities before merge"
    should_trigger: true
  - prompt: "run the tests"
    should_trigger: false
---

## When to Use

**Automatic trigger:**
- Changes touch auth, crypto, payment, or API route files
- New dependencies added (`package.json`, `requirements.txt`, `go.mod` changed)
- Environment/config files modified

**Manual trigger:**
- `/security-gate` — run on current staged changes
- Before any deploy to production

**Not for:**
- Documentation-only changes
- CSS/styling changes
- Test file changes (unless testing security features)

---

## Procedure

### 1. Collect the Diff

```bash
git diff --staged  # or git diff main...HEAD for full branch diff
```

### 2. Classify Risk Level

| Files Changed | Risk |
|--------------|------|
| auth/, middleware/, crypto/ | HIGH — always scan |
| routes/, api/, controllers/ | MEDIUM — scan if new endpoints |
| models/, schema/ | MEDIUM — scan for injection |
| package.json, go.mod | MEDIUM — dependency supply chain |
| .env, config/ | CRITICAL — secrets exposure |
| styles/, docs/, tests/ | LOW — skip scan |

### 3. Send to Reviewer Security Review

```bash
echo "$diff" > /tmp/canuto-security-diff-$$.patch
codex exec --color never --profile reviewer \
  -s read-only --skip-git-repo-check \
  -o /tmp/canuto-security-result-$$.md \
  "$(cat <<'PROMPT'
[SECURITY REVIEW REQUEST]
You are a senior security engineer performing a pre-merge security audit.
Use maximum reasoning depth for this review.

--- CHANGES START ---
{diff}
--- CHANGES END ---

## Checklist (OWASP Top 10 + extras)

### Injection (A03:2021)
- [ ] SQL injection via string concatenation
- [ ] NoSQL injection via unvalidated objects
- [ ] Command injection via shell exec
- [ ] LDAP/XPath injection

### Broken Authentication (A07:2021)
- [ ] Hardcoded credentials or API keys
- [ ] Weak session management
- [ ] Missing rate limiting on auth endpoints
- [ ] Token exposure in logs or URLs

### Sensitive Data Exposure (A02:2021)
- [ ] Secrets in code (.env values, API keys, passwords)
- [ ] PII logged without masking
- [ ] Sensitive data in error messages
- [ ] Missing encryption for data at rest/transit

### Broken Access Control (A01:2021)
- [ ] Missing authorization checks
- [ ] IDOR (direct object reference without ownership check)
- [ ] Privilege escalation paths
- [ ] Missing RLS policies (Supabase)

### Security Misconfiguration (A05:2021)
- [ ] CORS wildcard or overly permissive
- [ ] Debug mode enabled in production config
- [ ] Default credentials or configurations
- [ ] Missing security headers

### XSS (A03:2021)
- [ ] Unescaped user input in HTML/templates
- [ ] innerHTML or dangerouslySetInnerHTML with user data
- [ ] Script injection via URL parameters

### Race Conditions
- [ ] TOCTOU (time-of-check-time-of-use)
- [ ] Double-spend / duplicate submission
- [ ] Concurrent access without locking

### Dependency Supply Chain
- [ ] New dependencies with known CVEs
- [ ] Typosquatting package names
- [ ] Unpinned versions with ^ or ~

## Output Format

{
  "verdict": "PASS" | "FAIL" | "WARN",
  "critical": [{ "file": "...", "line": N, "issue": "...", "fix": "..." }],
  "warnings": [{ "file": "...", "line": N, "issue": "...", "fix": "..." }],
  "notes": ["..."],
  "score": 0-10
}

FAIL if any critical issue found. WARN if only warnings. PASS if clean.

The diff is at /tmp/canuto-security-diff-$$.patch — read it and review.
PROMPT
)"
# Read result via: cat /tmp/canuto-security-result-$$.md
```

### 4. Process Verdict

| Verdict | Action |
|---------|--------|
| **PASS** (score >= 8) | Log `[Security] ✅ PASS (score: N/10)` → proceed |
| **WARN** (score 5-7) | Present warnings to user → proceed with acknowledgment |
| **FAIL** (score < 5 or critical) | **BLOCK** merge → present issues → require fixes |

### 5. Fix Critical Issues

If FAIL:
1. Present issues to user with recommended fixes
2. After fixes, re-run security gate
3. Max 2 re-scans (prevent infinite loops)

---

## Integration with CSO Skill

This gate complements the `/cso` skill:
- `/cso` — comprehensive periodic audit (weekly/monthly)
- `/security-gate` — lightweight pre-merge check (every merge)

The security gate feeds data to CSO's trend tracking.

---

## Graceful Degradation

- reviewer MCP unavailable → Claude performs security review (less thorough)
- No diff available → scan full files in changed list
- Log: `[Security] ⚠️ Using Claude fallback (reviewer path unavailable)`

---

## Anti-Patterns

- DO NOT skip for "small changes" to auth code — small changes cause big breaches
- DO NOT auto-pass based on file type alone — context matters
- DO NOT treat WARN as PASS — warnings are actionable
- DO NOT scan test files for security (unless they test security features)
