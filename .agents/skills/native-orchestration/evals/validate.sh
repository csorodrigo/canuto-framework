#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../../../.." && pwd)"
SKILL_DIR="$ROOT/.agents/skills/native-orchestration"
AGENT_DIR="$ROOT/.codex/agents"

fail() {
  printf 'FAIL: %s\n' "$1" >&2
  exit 1
}

[ -f "$SKILL_DIR/SKILL.md" ] || fail "SKILL.md missing"
[ -f "$SKILL_DIR/agents/openai.yaml" ] || fail "openai.yaml missing"
[ -f "$SKILL_DIR/references/assignment-contract.md" ] || fail "assignment contract missing"
[ -f "$SKILL_DIR/references/result-contract.md" ] || fail "result contract missing"
[ -f "$SKILL_DIR/evals/cases.yaml" ] || fail "eval cases missing"

grep -q '^status: quarantine$' "$SKILL_DIR/SKILL.md" || fail "skill is not quarantined"
grep -q '^  allow_implicit_invocation: false$' "$SKILL_DIR/agents/openai.yaml" \
  || fail "implicit invocation must remain disabled"

agents=(canuto_native_scout canuto_native_reviewer)
for agent in "${agents[@]}"; do
  file="$AGENT_DIR/$agent.toml"
  [ -f "$file" ] || fail "missing native agent: $agent"
  grep -q '^name = ' "$file" || fail "$agent missing name"
  grep -q '^description = ' "$file" || fail "$agent missing description"
  grep -q '^sandbox_mode = "read-only"$' "$file" || fail "$agent is not read-only"
  grep -q '^developer_instructions = ' "$file" || fail "$agent missing developer instructions"
  grep -qi 'never delegate' "$file" || fail "$agent does not prohibit delegation"
  if grep -Eq '^(model|model_reasoning_effort)[[:space:]]*=' "$file"; then
    fail "$agent pins model or effort outside canonical routing"
  fi
  if grep -q 'workspace-write' "$file"; then
    fail "$agent requests mutable sandbox"
  fi
done

count=$(find "$AGENT_DIR" -maxdepth 1 -type f -name 'canuto_native_*.toml' | wc -l | tr -d ' ')
[ "$count" = "2" ] || fail "quarantine must define exactly two native agents, found $count"

for forbidden in canuto_native_worker canuto_native_coder canuto_native_deployer canuto_native_critic; do
  [ ! -e "$AGENT_DIR/$forbidden.toml" ] || fail "forbidden mutable/escalation agent exists: $forbidden"
done

printf 'PASS: native-orchestration quarantine invariants hold\n'
