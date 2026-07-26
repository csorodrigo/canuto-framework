shortDescription: Diagnose framework setup integrity and detect misconfigurations before they cause session failures.
usedBy: [maestro]
version: 1.3.0
lastUpdated: 2026-03-30
copyright: Rodrigo Canuto © 2026.
evals:
  - prompt: "somethings off with the framework, can u check if everythings configured ok? just started a new session"
    should_trigger: true
  - prompt: "personas arent responding properly, maybe something broke in the setup"
    should_trigger: true
  - prompt: "the coder persona made a mistake, can you review its output?"
    should_trigger: false
  - prompt: "is my obsidian vault syncing correctly?"
    should_trigger: false

## When to Use

**Triggers:**
- User says: `"health check"`, `"is the framework ok?"`, `"diagnose"`, `"check framework"`
- Maestro detects unexpected behavior (missing persona response, incomplete handoff, corrupted memory file)
- At session start in a freshly cloned or bootstrapped project

**Not for:**
- Mid-task interruptions — run at session start or on demand only
- Projects not using the Canuto Framework

---

## Purpose

Detect broken or missing framework components before they silently degrade session quality. The health check can be triggered on demand or automatically when something seems off.

---

## Checklist

### CLAUDE.md
- [ ] File exists at project root.
- [ ] Contains `## Framework` section.
- [ ] Contains `## Preferences` section.
- [ ] Contains `## Project Rules` section.
- [ ] Contains `## On Session Start` section.

### Personas
- [ ] `.agents/personas/maestro.md` exists.
- [ ] `.agents/personas/architect.md` exists.
- [ ] `.agents/personas/coder.md` exists.
- [ ] `.agents/personas/reviewer.md` exists.
- [ ] `.agents/personas/contextualizer.md` exists.

### Core Skills
- [ ] `.agents/skills/` directory is non-empty.
- [ ] `context-maintenance.md` present, or `.agents/skills/context-maintenance/SKILL.md` present.
- [ ] `api-design.md` present.
- [ ] `metrics.md` present.
- [ ] `canuto-project-doctor.md` present.
- [ ] `canuto-session-end-learning.md` present.
- [ ] `canuto-rework-detector.md` present.
- [ ] `canuto-pending-triage.md` present.
- [ ] `obsidian-writeback-queue.md` present.

### Global Vault (Obsidian Memory)
- [ ] `~/.canuto/vault/` directory exists.
- [ ] `~/.canuto/vault/_index.md` exists.
- [ ] `~/.canuto/vault/.obsidian/` config exists.
- [ ] `~/.canuto/vault/projects/{project-slug}/` directory exists (project-slug = basename of project dir).

### Vault Project Directories
- [ ] `projects/{project-slug}/sessions/` directory exists.
- [ ] `projects/{project-slug}/decisions/` directory exists.
- [ ] `projects/{project-slug}/instincts/` directory exists.
- [ ] `projects/{project-slug}/pending/` directory exists.
- [ ] `projects/{project-slug}/audit/` directory exists.
- [ ] `projects/{project-slug}/metrics/` directory exists.
- [ ] `projects/{project-slug}/design/` directory exists.
- [ ] `~/.canuto/vault/bases/` directory exists (global).
- [ ] `~/.canuto/vault/canvas/` directory exists (global).

### MCP
- [ ] `.agents/mcp/server.json` exists.
- [ ] `.agents/mcp/setup.md` exists.
- [ ] MCP connectivity: attempt `obsidian_list_notes(path="/")`. If MCP tools are available and Obsidian is running, this should return a list. If it fails, report as warning (not failure) — Obsidian may not be running.

### Obsidian Skills
- [ ] `.agents/skills/obsidian-markdown.md` exists (flat file, not in subdirectory).
- [ ] `.agents/skills/obsidian-markdown.md` exists (obsidian-bases/json-canvas foram arquivados 2026-07-26 — os .base/.canvas do vault continuam funcionando no app Obsidian sem os skills).
- [ ] `.agents/skills/mcp-obsidian.md` exists.

### Legacy Check
- [ ] `.agents/memory/` directory does NOT exist. If it does, warn: "Old flat-file memory detected. Run `bash install.sh --migrate` to upgrade."
- [ ] `.agents/skills/obsidian-markdown/SKILL.md` does NOT exist. If it does, warn: "Legacy obsidian-markdown skill structure detected (predates v1.6). Run `bash install.sh --update`."

### Skills Quality
- [ ] Critical skills have `evals` field in frontmatter: `health-check.md`, `auto-analysis.md`, `context-maintenance/SKILL.md`, `continuous-learning/SKILL.md`, `experiment-loop.md`, `browser-qa.md`, `knowledge-ingest.md`. Missing `evals` on a critical skill = WARNING.
- [ ] Skills >200 lines use subdirectory structure (`skill-name/SKILL.md` + `references/`). Oversized flat skills without progressive disclosure = WARNING.
- [ ] `frontend-design/` directory exists with `SKILL.md` and `references/` subdirectory (progressive disclosure pilot).

### Hooks
- [ ] `~/.claude/hooks/codex-pretool-guard.sh` exists and is executable.
- [ ] `~/.claude/hooks/screenshot-guard.sh` exists and is executable.
- [ ] `~/.claude/hooks/session-save.sh` exists and is executable.
- [ ] `~/.claude/hooks/session-load.sh` exists and is executable.
- [ ] `~/.claude/hooks/pre-compact-save.sh` exists and is executable.

### Codex Integration (v2.0, 2026-04-29 — CLI-only)
- [ ] `codex --version` returns OK.
- [ ] `~/.codex/config.toml` has 5 profiles (coder, reviewer, architect, fast, maestro), all on canonical model.
- [ ] `~/.claude/settings.json` does NOT have legacy `codex-coder` / `codex-reviewer` / `codex-maestro` MCP entries (re-run `bash install.sh --doctor` to clean).
- [ ] `~/.claude/settings.json` has `codex-pretool-guard.sh` on `PreToolUse`.
- [ ] `~/.claude/settings.json` has `screenshot-guard.sh` on `PreToolUse` with matcher `mcp__playwright__browser_take_screenshot|mcp__claude-in-chrome__computer`.
- [ ] `.agents/tools/codex-diff-context.sh` exists and is executable.
- [ ] `.agents/tools/codex-context-package.sh` exists and is executable.
- [ ] `.agents/tools/codex-health-check.sh` exists and is executable.
- [ ] `codex mcp list` works (Codex's own MCPs: obsidian-vault, ast-grep, playwright).
- [ ] `codex mcp get obsidian-vault --json` includes `OBSIDIAN_API_KEY` and `OBSIDIAN_BASE_URL`.
- [ ] Context preload assets exist (`.context.md`, `docs/FEATURE-MAP.md`) or are reported as warnings.

### CCB Plugin (arquivado 2026-07-26 — só se restaurado de `.agents/plugins/_archive/ccb/`)
- [ ] `ccb` command available in PATH (`which ccb`).
- [ ] `ask` command available in PATH (`which ask`).
- [ ] `pend` command available in PATH (`which pend`).
- [ ] Terminal multiplexer available (WezTerm or tmux).
- [ ] CCB daemon responsive (if running): check `~/.askd-state.json` exists.

### Tools
- [ ] `python3` is available (required for canvas generation and analyze.sh).
- [ ] `jq` is available (required for hooks and MCP setup).

### Global Vault Extras
- [ ] `~/.canuto/vault/global-instincts/` directory exists.
- [ ] `~/.canuto/vault/reports/` directory exists.
- [ ] At least 4 global bases exist in `~/.canuto/vault/bases/` (all-instincts, all-metrics, cross-project-patterns, global-instincts).

### SPEC
- [ ] `.agents/SPEC.md` exists.

### Learning Loop
- [ ] Session start can diagnose setup/memory/context drift via `canuto-project-doctor`.
- [ ] Rework/retry loops can be detected via `canuto-rework-detector`.
- [ ] Session end proposes decisions, pending tasks, metrics, and candidate instincts.
- [ ] Vault write-back is previewed or queued, not silent.
- [ ] Pending tasks remain concrete enough to act on.

---

## Output Format

```markdown
## Framework Health Check — YYYY-MM-DD

### ✅ Passing (N items)
- CLAUDE.md: all required sections present
- Personas: all 7 present
- Vault: directory structure intact, _index.md present
- MCP: server.json and setup.md present
- SPEC.md: present

### ⚠️ Warnings (N items)
- `.agents/skills/metrics.md` missing (metrics tracking disabled)
- `.agents/vault/bases/` empty (will be populated on first session end)

### ❌ Failures (N items)
- CLAUDE.md missing `## Framework` section → run `bash install.sh` to fix
- `.agents/personas/reviewer.md` missing → run `bash install.sh --update` to fix

### Verdict: HEALTHY | DEGRADED | BROKEN
```

**HEALTHY**: No failures, 0–2 warnings.  
**DEGRADED**: No failures, 3+ warnings or optional files missing.  
**BROKEN**: 1+ failures (critical files missing or malformed).

---

## Remediation Guide

| Issue | Recommended Fix |
|-------|-----------------|
| CLAUDE.md missing sections | `bash install.sh` (or curl one-liner) |
| Persona files missing | `bash install.sh --update` |
| Skill files missing | `bash install.sh --update` |
| Global vault missing | `bash install.sh` (creates `~/.canuto/vault/`) |
| Project vault dirs missing | `bash install.sh --update` (creates project subdirectories) |
| MCP config missing | Copy from `.agents/mcp/server.json` template |
| MCP not connecting | Check: Obsidian open? Local REST API plugin enabled? API key correct? See `.agents/mcp/setup.md` |
| Old memory/ exists | `bash install.sh --migrate` |
| Old skill SKILL.md in subdir | `bash install.sh --update` |
| SPEC.md missing | `bash install.sh --update` |
| Learning-loop skills missing | `bash install.sh --update` |
| Hooks missing | `bash install.sh --update` (reinstalls hooks) |
| Codex hooks/config degraded | `bash .agents/tools/codex-health-check.sh` |
| python3 missing | Install: `brew install python3` or `apt install python3` |
| jq missing | Install: `brew install jq` or `apt install jq` |
| CCB commands missing | `git clone https://github.com/bfly123/claude_code_bridge.git && cd claude_code_bridge && ./install.sh install` |
| CCB daemon not responding | Restart with `ccb` (daemon auto-starts) or kill stale `askd` process |
| global-instincts/ missing | `bash install.sh --update` (creates directory) |
| Global bases missing | `bash install.sh --update` (copies base templates) |

---

## Examples

### Good — structured report with verdict and remediation

```markdown
## Framework Health Check — 2026-03-21

### Passing (6 items)
- CLAUDE.md: all required sections present
- Personas: all 7 present
- Vault: structure intact, _index.md present, all 9 directories exist
- MCP: server.json and setup.md present, connectivity OK
- Obsidian skills: all 4 present (flat files)
- SPEC.md: present

### Warnings (1 item)
- .agents/vault/metrics/ empty (will be populated on first session end)

### Failures (0 items)

### Verdict: HEALTHY
```

### ❌ Bad — vague, unstructured check

```
The framework seems fine. I checked a few files and they look ok.
```

This is bad because: no itemized checklist, no verdict, no remediation steps — the user cannot tell what was verified, what passed, or what to fix.

---

## Guardrails

- Health check is **read-only**. Never modify files during the check.
- Report all issues, even warnings. Give the full picture.
- Do not run a health check mid-task. Run it before starting work or when explicitly requested.
- If verdict is BROKEN, Maestro must inform the user before proceeding with any task.
