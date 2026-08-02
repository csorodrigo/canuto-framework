shortDescription: Diagnose Canuto identity, installation, memory coverage, stale context, and learning-loop health before work starts.
usedBy: [maestro, reviewer]
version: 1.1.0
lastUpdated: 2026-08-01
copyright: Rodrigo Canuto © 2026.

## Purpose

Run a read-only project diagnosis that explains whether this repository is ready for productive agent work. This skill turns identity drift, framework drift, stale context, missing memory, missing skills, and repeated rework signals into a concrete remediation list.

Use it before risky work, after framework updates, or when a project feels confusing, stale, or inconsistent.

---

## Step 0 — Identity Gate (run FIRST, before anything else)

Every other check reads or reports memory. If the project's identity is wrong, all of them
diagnose the wrong vault and come back green — the failure mode edge-of-chaos ADR-0015 calls a
silent degrade (a baked-in identity scanned an empty store and reported "nothing new" for two
days, hiding 294 lost sessions). So identity resolves first, and it is allowed to fail the run.

```bash
source .agents/tools/canuto-memory.sh

canuto_fresh_clone_check "$PWD"        # informative, never fails the caller
canuto_classify_vault "" "$PWD"        # POPULATED | FRESH | ORPHAN  (ORPHAN exits 1)
canuto_require_project_slug "$PWD"     # write posture: prints the slug or exits 1 naming the gap
canuto_check_identity "$PWD"           # from .agents/tools/brief-compose.sh (front A4)
```

Read each verdict as follows:

| Signal | Verdict | What to report |
|--------|---------|----------------|
| `canuto_fresh_clone_check` → `TEMPLATE-CLONE` | **FAIL** | The repo declares the framework's own `project-slug` but is not the framework. Sessions here would be written into the framework's vault. Prescribe: run `canuto-init`, or fix `project-slug:` in `CLAUDE.md`. |
| `canuto_fresh_clone_check` → `UNINITIALIZED` | WARN | `.agents/` exists but nothing was ever written and no slug is declared. This is a fresh clone, not a live install — say so instead of reporting an empty-but-healthy memory. |
| `canuto_fresh_clone_check` → `NOT-CANUTO` | INFO | No `.agents/`. Diagnose as a foreign-schema project; do not demand Canuto structure. |
| `canuto_classify_vault` → `ORPHAN` (exit 1) | **FAIL** | Name the sibling from stderr: "slug `X` is empty but `Y` holds N notes for the same product — likely fragmentation; consolidate the two vaults or declare `project-slug`." Never report an orphan as a healthy fresh project. |
| `canuto_classify_vault` → `FRESH` | OK (with note) | Genuinely new project. Empty memory here is expected, not a defect — say "expected empty", never just leave the section blank. |
| `canuto_classify_vault` → `POPULATED` + stderr `aviso de fragmentação` | WARN | Both vaults hold notes for the same product. Prescribe consolidation or an entry in `.project-aliases.json`. |
| `canuto_require_project_slug` exits 1 | **FAIL** | Reproduce its stderr verbatim — it already names the gap (no `project-slug`, no `origin` remote, path outside a known container). Any write in this state lands in a guessed identity. |
| `canuto_check_identity` → `FAIL` | **FAIL** | The briefing composer cannot render this project's identity, or renders a declared-but-absent vault. Report the reason it printed. |

Rules for Step 0:

- A `FAIL` in Step 0 caps the whole run at **BROKEN** — never report `HEALTHY` on top of an
  unresolved identity, however clean the rest of the checklist looks.
- `ORPHAN` is a FAIL even though the vault *looks* empty and harmless: empty-but-siblings-full is
  exactly the fragmentation signature (edge-of-chaos `_validate._classify_graph`).
- The identity functions are the single source of this verdict. Do not re-derive a slug by hand
  from the path, the remote, or `CLAUDE.md` — a second resolution is how the two answers drift.

---

## Inputs To Check

- `CLAUDE.md`
- `.agents/SPEC.md`
- `.agents/personas/`
- `.agents/skills/`
- `.agents/memory/last-session.md`
- `.agents/memory/pending.md`
- `.agents/memory/decisions.md`
- `.agents/memory/metrics.md`
- `.context.md` files and `docs/FEATURE-MAP.md`
- Git status and recent commits, if shell access is allowed.
- Canuto vault project directory, resolved through `canuto-memory.sh` (never guessed).
- `<vault>/_health/slug-anomalies.jsonl` and `<vault>/_health/missing-lib.jsonl` — the honest
  degradation trail. Entries here mean something already degraded silently for the user.

This skill is read-only. Do not edit files during the diagnosis.

---

## Checklist

### Identity (Step 0 — blocking)

- `canuto_classify_vault` returns POPULATED or FRESH, and FRESH is labelled as expected-empty.
- `canuto_fresh_clone_check` returns OK (or NOT-CANUTO for a foreign-schema project).
- `canuto_require_project_slug` succeeds — the project can be *written to* without guessing.
- `canuto_check_identity` passes both legs.
- `_health/slug-anomalies.jsonl` has no entry for this repo (an entry means a copied template
  `CLAUDE.md` tried to write into another product's vault).

### Framework Installation

- Required personas are present.
- Required core skills are present.
- `CLAUDE.md` contains Framework, Preferences, Project Rules, and On Session Start sections.
- Installed skill versions look internally consistent.

### Memory Coverage

- `last-session.md` has a useful recent summary.
- `pending.md` contains concrete tasks, not broad intentions.
- `decisions.md` records architectural or product decisions when they exist.
- `metrics.md` has recent session entries, or the absence is explained.

### Learning Loop

- Session-end workflow captured done work, pending work, decisions, metrics, and rework signals.
- Errors and repeated attempts were promoted into decisions, pending items, or instincts.
- If Obsidian/Canuto vault is used, local memory and vault notes do not contradict each other.

### Stale Context

- `.context.md` files are newer than the source directories they summarize, or stale areas are listed.
- `docs/FEATURE-MAP.md` still matches current user-facing flows.
- Dirty files are grouped by likely intent: implementation, generated output, docs, temporary, unknown.

### Project Alignment

- The project is classified as Canuto, foreign-schema, or new.
- Conductor repo/workspace path and vault project path are linked, or the missing link is reported.
- Optional domain skills are installed only when useful for this project type.

---

## Output Format

```markdown
## Canuto Project Doctor - YYYY-MM-DD

### Verdict: HEALTHY | DEGRADED | BROKEN

### Findings
| Area | Status | Evidence | Impact |
|------|--------|----------|--------|
| Identity | OK/WARN/FAIL | <slug + classify/fresh-clone verdict + sibling, if any> | <wrong identity = every other check reads the wrong vault> |
| Framework | OK/WARN/FAIL | <path or observation> | <why it matters> |

### Immediate Fixes
1. <highest leverage fix>
2. <next fix>

### Optional Improvements
- <domain skill or workflow to install/adapt>

### Do Not Start Yet If
- <blocking condition, or "none">
```

---

## Guardrails

- **The doctor never fixes anything by itself: it diagnoses and prescribes.** No `canuto-init`,
  no vault consolidation, no `CLAUDE.md` edit, no alias written — every remediation goes into
  *Immediate Fixes* for a human to approve. A doctor that repairs is a doctor nobody can trust to
  report.
- Never modify files during the doctor run.
- Never mark the project HEALTHY if Step 0 produced any FAIL, or if required personas, core
  skills, or memory files are missing.
- Never let an empty vault pass as healthy without classifying it first (FRESH vs ORPHAN). "No
  notes" and "notes are in the wrong vault" look identical until `canuto_classify_vault` runs.
- Do not require Canuto schema for foreign-schema projects. Diagnose and adapt.
- Prefer a short, actionable report over a full file dump.
- If the project is BROKEN, Maestro must present the diagnosis before delegating any work.
