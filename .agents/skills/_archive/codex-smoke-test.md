---
skill: codex-smoke-test
trigger: install.sh --test, or /codex-test
persona: maestro
version: 2.0.0
lastUpdated: 2026-04-29
shortDescription: >
  Smoke test for Codex CLI integration. Verifies codex CLI + 5 profiles work.
  Run after install.sh setup or when troubleshooting.
usedBy: [maestro]
evals:
  - prompt: "test the codex integration"
    should_trigger: true
  - prompt: "verify codex profiles work"
    should_trigger: true
  - prompt: "fix a bug"
    should_trigger: false
---

## Purpose

After `install.sh` configures Codex CLI profiles, verify they actually work.
Tests: coder profile execution + reviewer profile one-shot call.

> Historical note (2026-04-29): previously tested `codex-coder` and
> `codex-reviewer` MCP servers. Those wrappers were retired; Codex is now
> invoked exclusively via CLI (`codex exec --profile <name>`).

---

## Tests

### Test 1: codex coder profile

```bash
codex exec --color never --profile coder \
  -s workspace-write --skip-git-repo-check \
  -o /tmp/codex-smoke-coder.md \
  "Write a file at .agents/tmp/codex-smoke-test.txt with content: CODEX_CODER_OK_$(date +%s)"
```

**Pass**: file exists with correct content.
**Fail**: timeout, error, or no file created.

### Test 2: codex reviewer profile

```bash
echo 'Review this trivial code and respond with JSON: {"verdict": "PASS", "test": true}

Code: const x = 1 + 1;' | codex exec --color never --profile reviewer \
  -s read-only --skip-git-repo-check \
  -o /tmp/codex-smoke-reviewer.md -
```

**Pass**: response contains `"verdict": "PASS"`.
**Fail**: timeout, error, or no response.

### Test 3: Codex Native MCPs (optional)

```bash
codex mcp list
```

**Pass**: shows obsidian-vault, ast-grep, playwright.
**Fail**: missing entries (warn, not block).

---

## install.sh Integration

```bash
smoke_test_codex() {
  log "Running Codex smoke test..."

  # Test 1: codex CLI is accessible
  if ! codex --version &>/dev/null; then
    warn "Codex CLI not responding"
    return 1
  fi
  ok "Codex CLI: $(codex --version 2>/dev/null)"

  # Test 2: ~/.codex/config.toml has 5 profiles with canonical model
  local config_toml="$HOME/.codex/config.toml"
  if [ -f "$config_toml" ]; then
    for profile in coder reviewer architect fast maestro; do
      if grep -q "\[profiles\.$profile\]" "$config_toml" 2>/dev/null; then
        ok "profile present: $profile"
      else
        warn "profile missing: $profile (re-run install.sh --doctor)"
      fi
    done
  else
    warn "$config_toml missing — run install.sh --doctor"
  fi

  # Test 3: codex mcp list (Codex's own MCPs: obsidian-vault, ast-grep, playwright)
  if codex mcp list &>/dev/null; then
    local mcp_count
    mcp_count=$(codex mcp list 2>/dev/null | wc -l)
    ok "Codex native MCPs: $mcp_count registered"
  else
    warn "codex mcp list not available"
  fi

  # Test 4: legacy MCP entries cleaned up
  local settings="$HOME/.claude/settings.json"
  if command -v jq &>/dev/null && [ -f "$settings" ]; then
    for legacy in codex-coder codex-reviewer codex-maestro; do
      if jq -e --arg s "$legacy" '.mcpServers[$s]' "$settings" &>/dev/null; then
        warn "legacy MCP entry present: $legacy (run install.sh --doctor to clean)"
      fi
    done
  fi

  ok "Smoke test complete"
}
```

---

## CLI Usage

```bash
# From install.sh
bash install.sh --test

# From Claude session
/codex-test
```

---

## Graceful Degradation

Smoke test failures are warnings, not errors. The framework works without Codex
(graceful degradation to Claude-only). The test just confirms optimal setup.
