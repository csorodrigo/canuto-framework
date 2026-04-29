---
skill: codex-smoke-test
trigger: install.sh --test, or /codex-test
persona: maestro
version: 1.0.0
lastUpdated: 2026-03-30
shortDescription: >
  Smoke test for Codex MCP integration. Verifies codex-coder and codex-reviewer
  are working. Run after install.sh setup or when troubleshooting.
usedBy: [maestro]
evals:
  - prompt: "test the codex integration"
    should_trigger: true
  - prompt: "verify codex mcps are working"
    should_trigger: true
  - prompt: "fix a bug"
    should_trigger: false
---

## Purpose

After `install.sh` configures Codex MCPs, verify they actually work.
Tests: spawn_agent with trivial task + one-shot reviewer call.

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

  # Test 2: codex-as-mcp is installable
  if command -v uvx &>/dev/null; then
    uvx codex-as-mcp@latest --help &>/dev/null \
      && ok "codex-as-mcp: available" \
      || warn "codex-as-mcp: not available (uvx issue)"
  fi

  # Test 3: codex mcp list
  if codex mcp list &>/dev/null; then
    local mcp_count
    mcp_count=$(codex mcp list 2>/dev/null | wc -l)
    ok "Codex native MCPs: $mcp_count registered"
  else
    warn "codex mcp list not available (v0.40+ required)"
  fi

  # Test 4: settings.json has both MCPs
  local settings="$HOME/.claude/settings.json"
  if command -v jq &>/dev/null && [ -f "$settings" ]; then
    local has_coder has_reviewer
    has_coder=$(jq -e '.mcpServers["codex-coder"]' "$settings" 2>/dev/null && echo "yes" || echo "no")
    has_reviewer=$(jq -e '.mcpServers["codex-reviewer"]' "$settings" 2>/dev/null && echo "yes" || echo "no")
    [ "$has_coder" = "yes" ] && ok "settings.json: codex-coder ✓" || warn "settings.json: codex-coder missing"
    [ "$has_reviewer" = "yes" ] && ok "settings.json: codex-reviewer ✓" || warn "settings.json: codex-reviewer missing"
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
