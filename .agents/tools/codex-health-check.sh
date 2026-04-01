#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
PROJECT_DIR="${CLAUDE_PROJECT_DIR:-$(pwd)}"
ROOT_DIR="$(cd "$PROJECT_DIR" && git rev-parse --show-toplevel 2>/dev/null || printf '%s\n' "$SCRIPT_ROOT")"

if [ ! -f "$ROOT_DIR/.agents/tools/codex-common.sh" ]; then
  ROOT_DIR="$SCRIPT_ROOT"
fi

# shellcheck source=/dev/null
source "$ROOT_DIR/.agents/tools/codex-common.sh"

MODE="full"
JSON_OUTPUT=false

while [ $# -gt 0 ]; do
  case "$1" in
    --smoke)
      MODE="structural"
      ;;
    --structural)
      MODE="structural"
      ;;
    --json)
      JSON_OUTPUT=true
      ;;
  esac
  shift
done

PASS=0
WARN=0
FAIL=0
ITEMS_FILE=$(mktemp)

cleanup() {
  rm -f "$ITEMS_FILE"
}
trap cleanup EXIT

record() {
  local status="$1"
  local message="$2"
  printf '%s\t%s\n' "$status" "$message" >> "$ITEMS_FILE"
}

pass() {
  PASS=$((PASS + 1))
  record "PASS" "$1"
  if [ "$JSON_OUTPUT" = false ]; then
    echo "  PASS  $1"
  fi
}

warn() {
  WARN=$((WARN + 1))
  record "WARN" "$1"
  if [ "$JSON_OUTPUT" = false ]; then
    echo "  WARN  $1"
  fi
}

fail() {
  FAIL=$((FAIL + 1))
  record "FAIL" "$1"
  if [ "$JSON_OUTPUT" = false ]; then
    echo "  FAIL  $1"
  fi
}

run_codex_smoke_exec() {
  local label="$1"
  shift
  local tmp_output
  local tmp_error
  tmp_output=$(mktemp)
  tmp_error=$(mktemp)

  if printf '%s\n' 'Reply with exactly: OK' | codex exec -C "$PROJECT_ROOT" --skip-git-repo-check "$@" --output-last-message "$tmp_output" - >/dev/null 2>"$tmp_error"; then
    local output
    output=$(tr -d '\r' < "$tmp_output" | tail -n 1 | tr -d '\n')
    if [ "$output" = "OK" ]; then
      pass "$label"
    else
      fail "$label returned unexpected output: ${output:-<empty>}"
    fi
  else
    fail "$label failed: $(head -n 1 "$tmp_error")"
  fi

  rm -f "$tmp_output" "$tmp_error"
}

run_codex_reviewer_profile_smoke() {
  local tmp_output
  local tmp_error
  tmp_output=$(mktemp)
  tmp_error=$(mktemp)

  if printf '%s\n' 'Reply with exactly: OK' | codex exec -C "$PROJECT_ROOT" --skip-git-repo-check --profile reviewer --output-last-message "$tmp_output" - >/dev/null 2>"$tmp_error"; then
    local output
    output=$(tr -d '\r' < "$tmp_output" | tail -n 1 | tr -d '\n')
    if [ "$output" = "OK" ]; then
      pass "reviewer profile smoke test"
    else
      warn "reviewer profile returned unexpected output: ${output:-<empty>}"
    fi
  else
    warn "reviewer profile unavailable: $(head -n 1 "$tmp_error")"
  fi

  rm -f "$tmp_output" "$tmp_error"
}

run_codex_reviewer_helper_smoke() {
  local tmp_dir
  tmp_dir=$(mktemp -d)
  local schema_file="$tmp_dir/schema.json"
  local prompt_file="$tmp_dir/prompt.txt"
  local output_file="$tmp_dir/output.json"
  local used_file="$tmp_dir/used.txt"
  local error_file="$tmp_dir/error.txt"

  cat > "$schema_file" <<'EOF'
{"type":"object","additionalProperties":false,"required":["verdict","summary","score","issues"],"properties":{"verdict":{"type":"string","enum":["LGTM","CONCERNS"]},"summary":{"type":"string"},"score":{"type":"number"},"issues":{"type":"array","items":{"type":"object","additionalProperties":false,"required":["severity","issue","fix"],"properties":{"severity":{"type":"string","enum":["high","medium","low"]},"issue":{"type":"string"},"fix":{"type":"string"}}}}}}
EOF

  cat > "$prompt_file" <<'EOF'
You are reviewing an implementation plan before coding starts.
Return JSON only, matching the provided schema.
Use verdict LGTM.
Plan:
- Step 1: Confirm the helper works.
EOF

  if codex_run_reviewer "$tmp_dir" "$schema_file" "$output_file" "$prompt_file" "$used_file" "$error_file"; then
    local used_candidate
    used_candidate=$(cat "$used_file" 2>/dev/null || echo "unknown")
    pass "reviewer helper smoke test: $used_candidate"
  else
    fail "reviewer helper smoke test failed: $(head -n 1 "$error_file")"
  fi

  rm -rf "$tmp_dir"
}

if [ "$JSON_OUTPUT" = false ]; then
  echo ""
  echo "Codex Integration Health Check"
  echo ""
fi

PROJECT_ROOT=$(codex_project_dir)
CONFIG_TOML="$HOME/.codex/config.toml"
CLAUDE_SCRIPTS_DIR="$HOME/.claude/scripts"
EXPECTED_CODEX_CODER="$CLAUDE_SCRIPTS_DIR/codex-coder.sh"
EXPECTED_CODEX_REVIEWER="$CLAUDE_SCRIPTS_DIR/codex-reviewer.sh"
EXPECTED_CODEX_AGENT_MCP="$CLAUDE_SCRIPTS_DIR/codex-agent-mcp.py"

if [ "$MODE" = "full" ]; then
  if command -v codex >/dev/null 2>&1; then
    pass "codex CLI available: $(codex --version 2>/dev/null || echo unknown)"
  else
    fail "codex CLI not found"
  fi

  if [ -f "$CONFIG_TOML" ]; then
    for profile in coder reviewer architect fast maestro; do
      if grep -q "\[profiles\.$profile\]" "$CONFIG_TOML" 2>/dev/null; then
        pass "profile configured: $profile"
      else
        fail "missing profile in config.toml: $profile"
      fi
    done
  else
    fail "missing $CONFIG_TOML"
  fi

  SETTINGS_FILE="$HOME/.claude/settings.json"
  if [ -f "$SETTINGS_FILE" ] && command -v jq >/dev/null 2>&1; then
    for server in codex-coder codex-reviewer; do
      if jq -e --arg server "$server" '.mcpServers[$server]' "$SETTINGS_FILE" >/dev/null 2>&1; then
        pass "settings.json MCP present: $server"
      else
        fail "settings.json missing MCP: $server"
      fi
    done

    if jq -e --arg command "$EXPECTED_CODEX_CODER" '.mcpServers["codex-coder"].command == $command' "$SETTINGS_FILE" >/dev/null 2>&1; then
      pass "settings.json codex-coder points to wrapper script"
    else
      fail "settings.json codex-coder is not using $EXPECTED_CODEX_CODER"
    fi

    if jq -e --arg command "$EXPECTED_CODEX_REVIEWER" '.mcpServers["codex-reviewer"].command == $command' "$SETTINGS_FILE" >/dev/null 2>&1; then
      pass "settings.json codex-reviewer points to wrapper script"
    else
      fail "settings.json codex-reviewer is not using $EXPECTED_CODEX_REVIEWER"
    fi

    for hook_name in codex-pretool-guard.sh plan-review.sh; do
      if grep -q "$hook_name" "$SETTINGS_FILE" 2>/dev/null; then
        pass "settings.json hook registered: $hook_name"
      else
        fail "settings.json hook missing: $hook_name"
      fi
    done
  else
    fail "cannot inspect ~/.claude/settings.json"
  fi

  if [ -x "$EXPECTED_CODEX_CODER" ]; then
    pass "codex-coder wrapper installed: $EXPECTED_CODEX_CODER"
  else
    fail "codex-coder wrapper missing or not executable: $EXPECTED_CODEX_CODER"
  fi

  if [ -x "$EXPECTED_CODEX_REVIEWER" ]; then
    pass "codex-reviewer wrapper installed: $EXPECTED_CODEX_REVIEWER"
  else
    fail "codex-reviewer wrapper missing or not executable: $EXPECTED_CODEX_REVIEWER"
  fi

  if [ -x "$EXPECTED_CODEX_AGENT_MCP" ]; then
    pass "codex-agent MCP wrapper installed: $EXPECTED_CODEX_AGENT_MCP"
  else
    fail "codex-agent MCP wrapper missing or not executable: $EXPECTED_CODEX_AGENT_MCP"
  fi

  for hook_file in codex-pretool-guard.sh plan-review.sh session-save.sh session-load.sh pre-compact-save.sh; do
    if [ -x "$HOME/.claude/hooks/$hook_file" ]; then
      pass "installed hook executable: $hook_file"
    else
      fail "hook not installed/executable: ~/.claude/hooks/$hook_file"
    fi
  done

  if [ -f "$CONFIG_TOML" ] && grep -q "projects.\"$PROJECT_ROOT\"" "$CONFIG_TOML" 2>/dev/null; then
    pass "project trust configured for $PROJECT_ROOT"
  else
    fail "project trust missing for $PROJECT_ROOT"
  fi

  if command -v codex >/dev/null 2>&1 && codex mcp list >/dev/null 2>&1; then
    pass "codex mcp list is available"
    _MCP_TMP=$(mktemp)
    trap 'rm -f "$ITEMS_FILE" "$_MCP_TMP"' EXIT
    for server in obsidian-vault ast-grep playwright; do
      if codex mcp get "$server" --json >"$_MCP_TMP" 2>/dev/null; then
        if [ "$server" = "obsidian-vault" ]; then
          if jq -e '(.transport.env.OBSIDIAN_API_KEY // .env.OBSIDIAN_API_KEY) and (.transport.env.OBSIDIAN_BASE_URL // .env.OBSIDIAN_BASE_URL)' "$_MCP_TMP" >/dev/null 2>&1; then
            pass "obsidian-vault has required env configuration"
          else
            warn "obsidian-vault missing env configuration"
          fi
        else
          pass "codex native MCP present: $server"
        fi
      else
        warn "codex native MCP missing: $server"
      fi
    done
  else
    fail "codex mcp list unavailable"
  fi

  run_codex_smoke_exec "default codex exec smoke test"
  run_codex_smoke_exec "coder profile smoke test" --profile coder
  run_codex_reviewer_profile_smoke
  run_codex_reviewer_helper_smoke
else
  pass "structural mode: skipped user-environment Codex checks"
fi

for script_file in \
  "$ROOT_DIR/.agents/tools/canuto-memory.sh" \
  "$ROOT_DIR/.agents/tools/codex-common.sh" \
  "$ROOT_DIR/.agents/tools/codex-diff-context.sh" \
  "$ROOT_DIR/.agents/tools/codex-context-package.sh" \
  "$ROOT_DIR/.agents/tools/codex-health-check.sh" \
  "$ROOT_DIR/.agents/tools/codex-maestro.sh" \
  "$ROOT_DIR/.agents/tools/vault-sync.sh"; do
  if [ -x "$script_file" ]; then
    pass "tool executable: $(basename "$script_file")"
  else
    fail "tool missing or not executable: $script_file"
  fi
done

if find "$PROJECT_ROOT" -name '.context.md' -print -quit 2>/dev/null | grep -q .; then
  pass "at least one .context.md found"
else
  warn "no .context.md files found"
fi

if [ -f "$PROJECT_ROOT/docs/FEATURE-MAP.md" ]; then
  pass "docs/FEATURE-MAP.md present"
else
  warn "docs/FEATURE-MAP.md missing"
fi

if [ -f "$PROJECT_ROOT/CODEX.md" ] && grep -q "codex-maestro.sh" "$PROJECT_ROOT/CODEX.md" 2>/dev/null; then
  pass "CODEX.md rendered for direct Codex runtime"
else
  warn "CODEX.md missing direct Codex runtime marker"
fi

if find "$PROJECT_ROOT/.agents/vault/digests" -maxdepth 1 -type f ! -name '.gitkeep' -print -quit 2>/dev/null | grep -q .; then
  pass "context digests available"
else
  warn "no generated context digests found"
fi

if [ "$MODE" = "full" ]; then
  if [ -f "$PROJECT_ROOT/.agents/tmp/context-package.md" ] || find "$PROJECT_ROOT/.agents/tmp" -maxdepth 1 -type f -name 'context-package*.md' -print -quit 2>/dev/null | grep -q .; then
    pass "context package available in .agents/tmp/"
  else
    warn "no context package found in .agents/tmp/"
  fi

  if command -v codex >/dev/null 2>&1; then
    if timeout 30 codex exec --profile reviewer --ephemeral -s read-only "Reply with exactly: OK" 2>/dev/null | grep -q "OK"; then
      pass "o1-pro model available (reviewer profile)"
    else
      warn "o1-pro model unavailable — reviewer/maestro calls will fall back"
    fi
  fi
fi

VERDICT="HEALTHY"
EXIT_CODE=0
if [ "$FAIL" -gt 0 ]; then
  VERDICT="BROKEN"
  EXIT_CODE=1
elif [ "$WARN" -gt 0 ]; then
  VERDICT="DEGRADED"
fi

if [ "$JSON_OUTPUT" = true ]; then
  python3 - "$ITEMS_FILE" "$PROJECT_ROOT" "$MODE" "$VERDICT" "$PASS" "$WARN" "$FAIL" <<'PYEOF'
import json
import sys

items_file, project_root, mode, verdict, pass_count, warn_count, fail_count = sys.argv[1:]
results = []
with open(items_file, encoding="utf-8") as fh:
    for line in fh:
        status, message = line.rstrip("\n").split("\t", 1)
        results.append({"status": status, "message": message})

print(json.dumps({
    "tool": "codex-health-check",
    "project_root": project_root,
    "mode": mode,
    "verdict": verdict,
    "counts": {
        "pass": int(pass_count),
        "warn": int(warn_count),
        "fail": int(fail_count),
    },
    "results": results,
}, ensure_ascii=True))
PYEOF
else
  echo ""
  if [ "$VERDICT" = "BROKEN" ]; then
    echo "Verdict: BROKEN ($FAIL failures, $WARN warnings, $PASS passing)"
  elif [ "$VERDICT" = "DEGRADED" ]; then
    echo "Verdict: DEGRADED ($WARN warnings, $PASS passing)"
  else
    echo "Verdict: HEALTHY ($PASS passing)"
  fi
fi

exit "$EXIT_CODE"
