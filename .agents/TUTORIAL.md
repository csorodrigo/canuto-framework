# Canuto Framework — Quick Start Guide

> Version 1.8 · Full specification: [SPEC.md](SPEC.md) · Technical reference for personas: `personas/` · Skills catalog: `skills/`

---

## §1 — Mental Model

Canuto is a **multi-persona AI framework** that gives Claude a persistent team structure and memory.

```
YOU  ←→  Maestro  ←→  Personas (Architect, Coder, Reviewer, ...)
                  ↕
              Vault (Obsidian)
         instincts · decisions · sessions · pending tasks
```

- **Maestro** is the orchestrator. You talk to Maestro. Maestro delegates.
- **Vault** is the memory. Everything learned in a session survives to the next.
- **Skills** are reusable playbooks. Maestro and personas consult them before acting.
- **Sessions are stateful.** What was decided, what failed, what was learned — all carries forward.

You never need to re-explain your project. The vault does it for you.

---

## §2 — Session Lifecycle

Every conversation follows this structure:

```
SESSION START                  DURING SESSION              SESSION END
─────────────                  ──────────────              ───────────
Load vault briefing            Maestro routes tasks        Mark goals ✅ ⏳ ❌
Check pending tasks            Instincts auto-applied      Trace analysis (v1.8)
Check stale contexts           Governance gates active     Extract instincts
Check blind-spot candidates    Rework detection on         Write session note
Set session goals (≤3)         Routing checks (v1.8)       Create pending tasks
Detect session mode            Coverage tracking (M/L)     Write metrics + audit
```

**Session modes** (detected automatically from what you say):

| Signal | Mode | Behavior |
|--------|------|----------|
| "Continue", "pick up where we left off" | `continue` | Resume pending tasks as goals |
| "Quick fix", "just this one thing" | `targeted` | Narrow scope, defer unrelated pending |
| New goal, no reference to prior work | `full` | Fresh start (default) |

---

## §3 — Personas Quick Reference

| Persona | Role | When active |
|---------|------|-------------|
| **Maestro** | Orchestrator. Routes, gates, tracks. Never codes. | Always — you talk to Maestro |
| **Architect** | Plans features. Interviews you. Produces structured plan + REQ-IDs. | S / M / L tasks |
| **Coder** | Implements per the plan. Writes basic tests. Updates `.context.md`. | After Architect (or directly for XS) |
| *Tester / Debugger* | Aposentados em 2026-06-11 — testes escritos pelo Coder no mesmo spawn; debugging via skill `/fix`. | — |
| **Reviewer** | Code review: correctness, style, plan alignment. | After Coder |
| **Contextualizer** | Scans codebase, generates `.context.md` + `FEATURE-MAP.md`. | New projects, context bootstrap |

---

## §4 — Task Routing

Maestro classifies every task before routing:

| Size | Criteria | Flow | Example |
|------|----------|------|---------|
| **XS** | Single file, low risk, no design | Maestro → Coder → Reviewer | Fix typo, tweak style, config change |
| **S** | 1-2 files, known scope | Maestro → Architect (brief) → Coder → Reviewer | Add a button, small endpoint |
| **M** | 3-5 files, integration | Maestro → Architect → Coder (implementa + testes) → Reviewer | New feature, form + API + state |
| **L** | Module / service, arch change | Maestro → Architect → Coder (implementa + testes) → Reviewer | Auth system, new data model |

Maestro announces the classification:
```
[Task S] Routing to Architect for abbreviated planning.
```

**Before routing**, Maestro automatically runs two passive checks:
1. **Skill Check (Step 0)** — is there a skill that applies?
2. **Instinct Lookup (Step 0.5)** — are there vault instincts relevant to this task? If so, they are injected into the handoff constraints automatically.

---

## §5 — Vault Memory

The vault lives at `~/.canuto/vault/projects/{project-slug}/`.

### What gets saved automatically
| Note type | Path | When created |
|-----------|------|--------------|
| Session note | `sessions/YYYY-MM-DD.md` | Session end |
| Metrics | `metrics/YYYY-MM-DD-metrics.md` | Session end |
| Audit event | `audit/YYYY-MM-DD-SESSION_END.md` | Session end |

### What requires your approval
| Note type | Path | How triggered |
|-----------|------|---------------|
| Instinct | `instincts/I-NNN-slug.md` | Maestro proposes at session end — you approve |
| Decision | `decisions/D-NNN-slug.md` | Created when a significant architectural choice is made |
| Pending task | `pending/task-slug.md` | Deferred work items from any session |

### Querying the vault
- Obsidian: open `~/.canuto/vault/` → use search or bases
- Via MCP (in session): Maestro uses `obsidian_global_search()` automatically
- Bases (Obsidian database views): `bases/instincts-by-confidence.base`, `bases/metrics-dashboard.base`

### Instinct lifecycle
```
Session → pattern detected → low confidence (I-NNN)
                           ↓ (2-3 occurrences)
                        medium confidence
                           ↓ (4+ occurrences, 5+ applied)
                        high confidence → candidate for global promotion
```

---

## §6 — Skills Cheatsheet

Skills are playbooks that personas follow. You can also invoke them directly.

| Skill | Trigger phrase | What it does |
|-------|----------------|--------------|
| `health-check` | "health check", "diagnose the framework" | Validates full framework setup — personas, vault, MCP, hooks |
| `context-maintenance` | "update context", "refresh .context.md" | Regenerates `.context.md` + `FEATURE-MAP.md` |
| `trace-analysis` | (runs at session end before instincts) | Classifies session signals: playbook gaps, blind-spot gaps, routing misfires, skill gaps |
| `continuous-learning` | (runs at session end via Maestro) | Extracts instincts from session patterns (fed by trace-analysis) |
| `auto-analysis` | "analyze the project", "cross-reference projects" | Deep scan → generates `project-index.json` + `onboarding-report.md` |
| `skill-creator` | "create a new skill" | 7-phase workflow for building new framework skills |
| `vault-maintenance` | "clean up vault", "archive sessions" | Archives old sessions, aggregates metrics, prunes orphans |
| `session-goals` | (runs at session start via Maestro) | Sets and tracks up to 3 goals per session |
| `design-consultation` | "create a design system", "brand guidelines" | Full design system → `design-system/MASTER.md` |
| `browser-qa` | "test the app", "QA this page" | Headless browser testing via Chrome DevTools MCP |
| `research` | "research X", "investigate migration to Y" | Community intelligence search (Reddit, HN, docs) |

> Full inventory: see [SPEC.md §10 Skills Inventory](SPEC.md) or list `.agents/skills/`.

---

## §7 — Common Workflows

### Start a new feature
```
You: "Add user profile page with avatar upload"
→ Maestro classifies as M
→ Maestro: Skill Check + Instinct Lookup
→ Maestro → Architect (interview + plan)
→ Architect → Coder (implements steps)
→ Coder (implementa + testes, incl. edge cases)
→ Coder → Reviewer (code review)
→ Reviewer → Maestro (summary)
```

### Fix a known bug
```
You: "The login button doesn't work on Safari"
→ Maestro classifies as XS or S
→ Maestro → Coder → Reviewer
```

### Fix an unknown bug (root cause unclear)
```
You: "Users are getting logged out randomly"
→ Maestro → fluxo /fix (diagnoses root cause, raiz confirmada + fingerprint)
→ /fix → Coder (implements fix + tests)
→ Coder → Reviewer
```

### Bootstrap a new project
```
You: "Set up Canuto on this project"
→ /canuto-init (or: "initialize Canuto here")
→ Maestro → Contextualizer
→ Contextualizer creates .context.md + FEATURE-MAP.md
```

### Clean up memory after many sessions
```
You: "clean up the vault" or /vault-maintenance
→ Archives sessions older than 30 days
→ Aggregates metrics
→ Prunes low-confidence stale instincts
```

### Check framework health
```
You: "health check" or /health-check
→ Maestro runs health-check skill inline
→ Output: HEALTHY / DEGRADED / BROKEN + itemized list
```

### See what was done last session
```
You: (just start a new conversation)
→ Maestro automatically presents a 5-line briefing from vault
→ Includes: last session summary, deferred goals, pending tasks, active instincts
```

---

## §8 — v1.8: Self-Improving Agent Loop (AutoAgent-inspired)

v1.8 adds trace-based learning, inspired by [AutoAgent](https://github.com/kevinrgu/autoagent). The framework now systematically mines session traces to propose improvements.

### How it works

```
SESSION END (Maestro)
  1. Trace Analysis ← reads audit events, metrics, session note
     ↓ classifies signals
  2. Outputs:
     - vault/traces/{date}-digest.md     (signal digest)
     - blind-spots/_candidates/*.md       (new pitfall proposals)
     - instinct-candidate signals         (fed to continuous-learning)
  3. Continuous Learning ← receives candidates, asks user approval
```

### New capabilities

| Feature | What it does | How to use |
|---------|-------------|------------|
| **Trace analysis** | Mines session data for actionable signals | Automatic at session end (needs `CANUTO_TRACE_ANALYSIS=1`) |
| **Auto blind spots** | Proposes new domain pitfalls from session failures | Candidates shown at next session briefing |
| **Adaptive routing** | Detects wrong task sizing mid-session | Maestro suggests reroute after Architect/Coder handoff |
| **Skill auto-discovery** | Detects recurring manual workflows | Proposes skill creation after 3+ occurrences |
| **Experiment auto-triggers** | Finds weak review score dimensions | Proposes experiment series (never auto-starts) |

### Enabling trace analysis

Set the env var before starting a session:
```bash
export CANUTO_TRACE_ANALYSIS=1
```

Or add to your shell profile (`~/.zshrc`):
```bash
export CANUTO_TRACE_ANALYSIS=1
```

### Blind-spot candidate lifecycle

```
trace-analysis detects gap → creates _candidates/{domain}--{slug}.md
                                          ↓
next session briefing → Maestro presents candidates
                                          ↓
              [promote] → appended to blind-spot file + archived
              [dismiss] → moved to .archive/
              [review]  → read full candidate before deciding
```

### Routing check example

```
[Maestro] Routing Check
Sizing: S | Architect produced 6 steps across 5 files
Signal: blast radius exceeds S threshold (1-2 files)
Recommendation: Promote to M, exigir testes completos do Coder
Proceed with reroute? [Promote to M / Keep S]
```

### Overfitting guard

Every trace-analysis proposal is tested: **"If this exact task disappeared, would this still matter?"** If no, the signal is recorded but not promoted.

---

## Key Files Reference

| File | Purpose |
|------|---------|
| `CLAUDE.md` (project root) | Main entrypoint. Framework config + project rules. |
| `.agents/SPEC.md` | Full technical specification. |
| `.agents/personas/maestro.md` | Maestro playbook — session lifecycle + routing rules. |
| `.agents/skills/health-check.md` | Framework integrity checklist (112 items). |
| `~/.canuto/vault/` | Global Obsidian vault with all project memories. |
| `.agents/.cache/last-briefing.txt` | Cached briefing for offline recovery. |

---

*Auto-maintained by the Canuto Framework. For changes, follow the skill-creator workflow.*
