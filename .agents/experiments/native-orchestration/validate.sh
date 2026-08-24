#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../../.." && pwd)"
EXPERIMENT_DIR="$ROOT/.agents/experiments/native-orchestration"
CANDIDATE_ROOT="$EXPERIMENT_DIR/candidate"
SKILL_DIR="$CANDIDATE_ROOT/.agents/skills/native-orchestration"
AGENT_DIR="$CANDIDATE_ROOT/.codex/agents"

fail() {
  printf 'FAIL: %s\n' "$1" >&2
  exit 1
}

[ -f "$EXPERIMENT_DIR/README.md" ] || fail "quarantine README missing"
[ -f "$SKILL_DIR/SKILL.md" ] || fail "candidate SKILL.md missing"
[ -f "$SKILL_DIR/agents/openai.yaml" ] || fail "candidate openai.yaml missing"
[ -f "$SKILL_DIR/references/assignment-contract.md" ] || fail "assignment contract missing"
[ -f "$SKILL_DIR/references/result-contract.md" ] || fail "result contract missing"
[ -f "$SKILL_DIR/references/adversarial-review.md" ] || fail "adversarial review missing"
[ -f "$SKILL_DIR/evals/cases.yaml" ] || fail "eval cases missing"

[ ! -e "$ROOT/.agents/skills/native-orchestration" ] \
  || fail "active root skill copy exists; quarantine is no longer inert"

if find "$ROOT/.codex/agents" -maxdepth 1 -type f -name 'canuto_native_*.toml' -print -quit 2>/dev/null | grep -q .; then
  fail "active root native agent copy exists; quarantine is no longer inert"
fi

grep -q '^status: quarantine$' "$SKILL_DIR/SKILL.md" || fail "candidate skill is not quarantined"
grep -q '^  allow_implicit_invocation: false$' "$SKILL_DIR/agents/openai.yaml" \
  || fail "implicit invocation must remain disabled"

agents=(canuto_native_scout canuto_native_reviewer)
for agent in "${agents[@]}"; do
  file="$AGENT_DIR/$agent.toml"
  [ -f "$file" ] || fail "missing candidate native agent: $agent"
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

printf 'PASS: native-orchestration candidate is inert and quarantine invariants hold\n'
