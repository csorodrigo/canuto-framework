#!/usr/bin/env bash
# observability-smoke.sh — health probes for Canuto OTel stack (SigNoz + Claude Code + Codex)
#
# Usage:
#   observability-smoke.sh            # human-readable output
#   observability-smoke.sh --json     # JSON for install.sh --doctor consumption
#
# Rollback cheat sheet (see .agents/mcp/setup.md ## Rollback for details):
#   TS=<timestamp from backup>
#   cp ~/.claude/settings.json.bak.$TS  ~/.claude/settings.json
#   cp ~/.claude/CLAUDE.md.bak.$TS      ~/.claude/CLAUDE.md
#   cp ~/.codex/config.toml.bak.$TS     ~/.codex/config.toml
#   cd ~/signoz/deploy/docker && docker compose down -v
#   rm -f ~/.hammerspoon/init.lua ~/.wezterm.lua
#
# Exits 0 if all probes pass, 1 otherwise.
# Compatible with macOS bash 3.2 (no associative arrays).

set -o pipefail

JSON_MODE=0
[ "$1" = "--json" ] && JSON_MODE=1

# Run a probe: sets a variable "result_<name>" to "ok" or "fail".
probe() {
  local name="$1"; local cmd="$2"
  if eval "$cmd" &>/dev/null; then
    eval "result_${name}=ok"
  else
    eval "result_${name}=fail"
  fi
}

# Probe definitions (order matters for output).
PROBES="docker_daemon signoz_containers otlp_grpc_4317 otlp_http_4318 signoz_ui_8080 signoz_api_health claude_otel_env claude_otlp_ep codex_otel_section"

probe docker_daemon      "docker ps"
probe signoz_containers  "cd ~/signoz/deploy/docker 2>/dev/null && docker compose ps --format json | jq -se 'length>0 and all(.State==\"running\")'"
probe otlp_grpc_4317     "lsof -iTCP:4317 -sTCP:LISTEN"
probe otlp_http_4318     "lsof -iTCP:4318 -sTCP:LISTEN"
probe signoz_ui_8080     "curl -sf -o /dev/null http://localhost:8080"
probe signoz_api_health  "curl -sf http://localhost:8080/api/v1/health | jq -e '.status==\"ok\"'"
probe claude_otel_env    "jq -e '.env.CLAUDE_CODE_ENABLE_TELEMETRY==\"1\"' ~/.claude/settings.json"
probe claude_otlp_ep     "jq -er '.env.OTEL_EXPORTER_OTLP_ENDPOINT' ~/.claude/settings.json | grep -q '4317'"
probe codex_otel_section "grep -q '^\[otel\]' ~/.codex/config.toml"

# Aggregate result.
FAIL=0
for name in $PROBES; do
  eval "v=\$result_${name}"
  [ "$v" = "fail" ] && FAIL=1
done

if [ "$JSON_MODE" = "1" ]; then
  printf '{'
  first=1
  for name in $PROBES; do
    [ $first -eq 1 ] && first=0 || printf ','
    eval "v=\$result_${name}"
    printf '"%s":"%s"' "$name" "$v"
  done
  if [ $FAIL -eq 0 ]; then ov="ok"; else ov="fail"; fi
  printf ',"overall":"%s"}\n' "$ov"
else
  for name in $PROBES; do
    eval "v=\$result_${name}"
    if [ "$v" = "ok" ]; then
      printf '  \033[32m✓\033[0m %s\n' "$name"
    else
      printf '  \033[31m✗\033[0m %s\n' "$name"
    fi
  done
  if [ $FAIL -eq 0 ]; then
    printf '\n\033[32mAll probes OK\033[0m — SigNoz ready for Claude Code + Codex telemetry.\n'
    printf 'Dashboard: http://localhost:8080\n'
  else
    printf '\n\033[31mOne or more probes failed\033[0m — see .agents/mcp/setup.md ## Observability for troubleshooting.\n'
  fi
fi

exit $FAIL
