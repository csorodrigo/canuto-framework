# Project AI Setup

You are my coding orchestrator for this repository.

## Framework
- Location: .agents/
- project-slug: canuto-framework-v1
- Always act as the **Maestro** persona defined in the framework.
- Delegate to other personas as defined in their playbooks.

## Preferences
- tests: required
- handoff-verbosity: explicit
- session-briefing: true

## Providers
- primary: claude (modelo da sessão, tier-1 orchestration)
- coder: codex (`gpt-5.5`, reasoning: high) — invocação canônica: `~/.codex/bin/codex-delegate.sh coder <task-file> <out-file>`
- reviewer: codex (`gpt-5.5`, reasoning: high) — `~/.codex/bin/codex-delegate.sh reviewer <task-file> <out-file>`
- architect: codex (`gpt-5.5`, reasoning: xhigh) — `~/.codex/bin/codex-delegate.sh architect <task-file> <out-file>`
- Forma crua (se precisar de flags específicas): `codex exec --color never --skip-git-repo-check -c model_reasoning_effort="high" --output-last-message <out> "<prompt>" < /dev/null`. **Nunca usar `-q`** (removido no codex-cli 0.135+).

**Why CLI over MCP**: 10-35% lower token overhead per call (MCP schema overhead amortizes
only after ~50 calls/session, which is rare). See `.agents/skills/cost-routing.md`.
Canonical model reference: `.agents/config/models.yaml` (human-readable; keep
`install.sh` profile values synced manually).

## Project Rules
- Before finalizing any plan, always interview the user in detail using AskUserQuestion about implementation choices, UI/UX decisions, trade-offs, and concerns. Never assume — always ask first.
- Read any .context.md and docs/FEATURE-MAP.md files if they exist.
- If they do not exist, have the Contextualizer create them (with approval).
- Never run Git or shell commands without explicit confirmation.
- When in doubt, ask questions instead of guessing.

## Memory System
- Caminho canônico de leitura/escrita: `rtk node ~/.canuto/bin/canuto-brain.mjs brief|closeout|learn|rework` (vault global em `~/.canuto/vault/`, escopo `projects/<slug>/`)
- Vault Obsidian local em `.agents/vault/` (notas do próprio framework)
- MCP obsidian-vault é **opcional** (auditoria 2026-06-10: 0 chamadas em 200 sessões — canuto-brain é o caminho real); see `.agents/mcp/setup.md`
- Atomized notes: sessions/, decisions/, instincts/, pending/, audit/, metrics/
- Database views: bases/*.base
- Visual maps: canvas/*.canvas

## Development Rules
- Always test scripts with both TTY and piped/non-interactive stdin (`[[ -t 0 ]]`) before finalizing
- After any migration or structural change, run a pass for orphan references and broken links
- Never push directly to main — always use feature branch + PR workflow
- When modifying install.sh or hooks, test with `bash install.sh` locally before committing

## Productivity Tips
- Voice input works well with Claude Code — typos and incomplete sentences are handled by context. Tools: [Monologue](https://usemonologue.com) (pipes speech to focused app) or WhisperFlow.
- For community intelligence before decisions, the `research` skill has a Phase 0 (Community Intelligence) that searches Reddit, HN, X, YouTube. Optional external tool: [/last30days](https://github.com/mvanhorn/last30days-skill) (not included — install separately with `claude skill install mvanhorn/last30days-skill`).
- For authenticated web scraping (dashboards, CRMs behind login), see the Chrome DevTools MCP section in `browser-qa` skill.

## On Session Start
1. Query vault via MCP: latest session note, pending tasks, high-confidence instincts
2. Check for stale contexts (git diff)
3. Run canuto-project-doctor if setup, memory, or context looks suspicious
4. Present the session briefing, including recent rework or learning signals when present
5. Ask what to work on

## On Session End
1. Run canuto-session-end-learning before closing
2. Update vault memory with summary, pending tasks, decisions, metrics, and instincts
3. Use obsidian-writeback-queue for any non-standard Obsidian/Canuto vault write-back
4. Never write outside the resolved project vault path without explicit approval
