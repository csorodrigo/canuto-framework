#!/usr/bin/env bash
set -euo pipefail

# Gemini MCP smoke check — verifica que as skills Gemini estão distribuídas
# e referenciadas onde precisam. Não exige OAuth ativo.
# Se GEMINI_INTEGRATION=1, adiciona checks opcionais de runtime.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"
cd "$ROOT_DIR"

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[0;33m'; RESET='\033[0m'
ERRORS=0; WARN=0

check_file() {
  local f="$1"; local label="$2"
  if [ -f "$f" ]; then
    echo -e "  ${GREEN}✓${RESET} $label ($f)"
  else
    echo -e "  ${RED}✗${RESET} MISSING: $label ($f)"
    ERRORS=$((ERRORS + 1))
  fi
}

check_grep() {
  local pattern="$1"; local file="$2"; local label="$3"
  if [ -f "$file" ] && grep -q "$pattern" "$file"; then
    echo -e "  ${GREEN}✓${RESET} $label"
  else
    echo -e "  ${RED}✗${RESET} MISSING reference: $label"
    ERRORS=$((ERRORS + 1))
  fi
}

echo "== Gemini MCP smoke check =="
echo "  (running from $ROOT_DIR)"
check_file ".agents/skills/gemini-routing.md" "gemini-routing skill"
check_file ".agents/skills/bulk-classify.md" "bulk-classify skill"
check_grep "gemini-routing" ".agents/skills/cost-routing.md" "cost-routing references gemini-routing"
check_grep "gemini-routing" "CLAUDE.md" "CLAUDE.md references gemini-routing"
check_grep "[Gg]emini" "registry.md" "registry.md mentions Gemini"

if [ "${GEMINI_INTEGRATION:-0}" = "1" ]; then
  echo "== Runtime checks (GEMINI_INTEGRATION=1) =="
  if command -v gemini >/dev/null 2>&1; then
    echo -e "  ${GREEN}✓${RESET} gemini CLI present: $(gemini --version 2>/dev/null || echo unknown)"
  else
    echo -e "  ${YELLOW}⚠${RESET}  gemini CLI not on PATH"; WARN=$((WARN + 1))
  fi
  if command -v claude >/dev/null 2>&1 && claude mcp list 2>/dev/null | grep -qi gemini; then
    echo -e "  ${GREEN}✓${RESET} gemini MCP registered"
  else
    echo -e "  ${YELLOW}⚠${RESET}  gemini MCP not listed (run: claude mcp add gemini ...)"; WARN=$((WARN + 1))
  fi
fi

echo ""
echo "== Summary =="
if [ $ERRORS -gt 0 ]; then
  echo -e "${RED}FAIL${RESET}: $ERRORS errors, $WARN warnings"
  exit 1
else
  echo -e "${GREEN}PASS${RESET}: 0 errors, $WARN warnings"
fi
