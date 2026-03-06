#!/usr/bin/env bash
# plan-review.sh — Segunda opinião do Codex sobre planos do Architect
# Baseado em cathrynlavery/codex-skill (MIT), adaptado para o framework Canuto
# Dispara via PostToolUse: ExitPlanMode
#
# INSTALAÇÃO:
#   cp .agents/hooks/plan-review.sh ~/.claude/hooks/plan-review.sh
#   chmod +x ~/.claude/hooks/plan-review.sh

set -euo pipefail

# Falha silenciosa se Codex não estiver instalado
if ! command -v codex &> /dev/null; then
  exit 0
fi

# Ler input do hook (JSON com tool_input/tool_response via stdin)
HOOK_INPUT=$(cat)

# Tentar extrair o caminho do plano do output do hook
PLAN_FILE=$(echo "$HOOK_INPUT" | jq -r '.tool_response.plan_file_path // empty' 2>/dev/null || true)

# Se não encontrou via JSON, buscar no diretório do projeto
if [[ -z "$PLAN_FILE" ]]; then
  PLAN_FILE=$(find "${CLAUDE_PROJECT_DIR:-.}" -maxdepth 2 \
    \( -name "PLAN.md" -o -name "plan.md" -o -name "PLAN.txt" \) \
    -not -path "*/node_modules/*" \
    2>/dev/null | head -1 || true)
fi

# Tentar caminho padrão dos plans do Claude Code
if [[ -z "$PLAN_FILE" ]]; then
  PLANS_DIR="$HOME/.claude/plans"
  if [[ -d "$PLANS_DIR" ]]; then
    PLAN_FILE=$(ls -t "$PLANS_DIR"/*.md 2>/dev/null | head -1 || true)
  fi
fi

# Nada encontrado — sair silenciosamente
if [[ -z "$PLAN_FILE" ]] || [[ ! -f "$PLAN_FILE" ]]; then
  exit 0
fi

PLAN_CONTENT=$(cat "$PLAN_FILE")

PROMPT="You are a critical technical reviewer. Review this implementation plan and identify:
1. What could make this plan fail?
2. Missing edge cases or hidden dependencies?
3. Is there a simpler alternative?
4. Any unverified assumptions?

Be brief and decisive. Respond with EITHER:
- A single line: \"✓ LGTM — plano sólido\" (if the plan is solid)
- Up to 5 bullet points starting with \"- \" describing specific concerns (no headers, no preamble)

Plan to review:
---
${PLAN_CONTENT}
---"

echo ""
echo "════════════════════════════════"
echo "  Segunda Opinião — Codex"
echo "════════════════════════════════"

RESULT=$(codex exec \
  --dangerously-bypass-approvals-and-sandbox \
  -m gpt-4o \
  "$PROMPT" 2>/dev/null || echo "⚠️ Codex não retornou resultado.")

if echo "$RESULT" | grep -q "^✓"; then
  echo "✓ LGTM — plano sólido"
else
  echo "⚠️ Pontos de atenção:"
  echo "$RESULT" | grep "^- " | head -5
fi

echo "════════════════════════════════"
echo ""
