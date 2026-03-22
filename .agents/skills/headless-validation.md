shortDescription: Guide for running framework validation in headless/CI mode without interactive input.
usedBy: [maestro, tester]
version: 1.0.0
lastUpdated: 2026-03-21
copyright: Rodrigo Canuto © 2026.

## When to Use

**Triggers:**
- User says: `"validate in CI"`, `"headless mode"`, `"run tests non-interactively"`, `"CI pipeline"`
- Setting up GitHub Actions or any CI/CD pipeline for framework validation
- Testing install.sh or migration scripts in non-interactive environments

**Not for:**
- Interactive debugging sessions
- Local-only manual testing

---

## Purpose

Ensure that the Canuto Framework's scripts (install, migration, hooks, test suite) work correctly in non-interactive environments where `stdin` is not a TTY. This is critical for CI pipelines and automated validation.

---

## TTY Detection Pattern

All framework scripts that may run in CI **must** handle non-interactive stdin:

```bash
if [[ -t 0 ]]; then
  # Interactive — can prompt user
  read -p "Enter value: " value
else
  # Non-interactive (piped, CI, headless)
  # Use default or env var, skip interactive prompts
  value="${MY_VAR:-default}"
fi
```

### Where to Apply

| Script | TTY Concern | Solution |
|--------|-------------|----------|
| `install.sh` | API key prompt, confirmation prompts | Use `--api-key` flag or `OBSIDIAN_API_KEY` env var |
| `session-load.sh` | Vault access prompts | Graceful fallback if vault unavailable |
| `session-save.sh` | Backup confirmation | Auto-proceed in non-interactive mode |
| `check-references.sh` | None (read-only) | Already headless-safe |
| `check-orphans.sh` | None (read-only) | Already headless-safe |

---

## CI Validation Workflow

### GitHub Actions Setup

The framework includes `.github/workflows/validate-framework.yml` which runs:

1. **test-framework.sh** — Structure validation (personas, skills, hooks, vault)
2. **install.sh --check** — Dependency and integrity check
3. **Syntax check** — `bash -n` on all `.sh` files
4. **Frontmatter validation** — Ensures skills have required metadata
5. **Reference check** — Runs `check-references.sh` on vault files

### Running Locally (Headless)

To simulate CI locally:

```bash
# Simulate non-interactive environment
echo "" | bash test-framework.sh

# Or explicitly test with no TTY
bash test-framework.sh < /dev/null

# Check install script in check mode (no prompts)
bash install.sh --check

# Run reference and orphan checks
bash .agents/hooks/check-references.sh
bash .agents/hooks/check-orphans.sh
```

---

## Checklist for New Scripts

When adding new scripts to the framework, verify:

- [ ] Script handles `[[ -t 0 ]]` for all user prompts
- [ ] All interactive inputs have flag/env-var alternatives
- [ ] Script runs cleanly with `< /dev/null`
- [ ] Exit codes are meaningful (0 = success, 1 = failure, 2 = warning)
- [ ] Script is included in the CI workflow if it validates framework state
- [ ] Script is added to `test-framework.sh` hooks section
