shortDescription: How to group personas into squads for parallel or domain-specific work.
usedBy: [maestro]
version: 1.0.0
lastUpdated: 2026-02-25
copyright: Rodrigo Canuto © 2026.

## Purpose

As projects grow, a single sequential flow (Architect → Coder → Tester → Reviewer) can become a bottleneck. Squads allow the Maestro to organize personas into parallel workstreams, each tackling a different part of the system.

This is an **advanced feature** for larger projects or multi-feature sessions. For single-feature work, the standard flow is sufficient.

---

## What Is a Squad?

A squad is a **named group of personas assigned to a specific domain or task**. Each squad follows the standard flow independently, and the Maestro coordinates between squads.

```
Squad: "auth"
  Architect → Coder → Tester → Reviewer
  Domain: src/auth/, src/api/middleware/

Squad: "dashboard"
  Architect → Coder → Tester → Reviewer
  Domain: src/pages/dashboard/, src/components/charts/
```

---

## When to Use Squads

Use squads when:
- The session involves **2+ independent features** that don't share code paths.
- The project has **clear domain boundaries** (e.g., separate services, modules, or packages).
- The user explicitly requests parallel work.

Do NOT use squads when:
- Features share significant code (risk of merge conflicts).
- The project is small (single module, <20 files).
- The team is working on a single feature.

---

## Procedure

### 1. Identify Domains

Maestro analyzes the task(s) and identifies:
- Which directories/modules each task touches.
- Whether there is overlap between tasks.

If overlap > 30% of files → do NOT use squads. Run sequentially.

### 2. Define Squads

For each independent domain:

```markdown
## Squad: <name>

### Domain
- Directories: <list of directories this squad owns>
- Context files: <list of .context.md files to read>

### Task
- Goal: <what this squad must achieve>
- Plan: <reference to Architect's plan section>

### Personas
- Architect: plans this domain's changes
- Coder: implements within this domain
- Tester: tests this domain's changes
- Reviewer: reviews this domain's code
```

### 3. Coordinate Squads

Maestro:
1. Assigns tasks to squads.
2. Runs each squad's standard flow.
3. Tracks progress per squad.
4. Handles cross-squad dependencies:
   - If Squad A needs something from Squad B, Maestro pauses Squad A until Squad B delivers.
   - Dependencies are announced explicitly.

### 4. Merge Squad Results

After all squads complete:
1. Maestro reviews cross-cutting concerns:
   - Shared types or interfaces changed by multiple squads.
   - Integration points (API contracts, shared state).
2. If conflicts exist, Maestro delegates to the Architect for resolution.
3. Final review covers the combined output.

---

## Squad Configuration in CLAUDE.md

```markdown
## Squads
- mode: auto | manual | disabled
- max-parallel: 2
```

- **auto**: Maestro decides when to use squads based on task analysis.
- **manual**: User explicitly requests squads.
- **disabled**: Always use sequential flow.
- **max-parallel**: Maximum number of concurrent squads (default: 2).

---

## Session Briefing with Squads

When squads are active, the briefing includes:

```
Session Briefing:
- Active squads:
  - "auth" — Implementing JWT refresh flow (Step 2/4)
  - "dashboard" — Adding chart components (Step 1/3)
- Cross-squad dependencies: none currently.
- Pending: auth squad waiting for API contract from dashboard squad.
```

---

## Guardrails

- Maximum 3 squads per session. More than 3 becomes unmanageable.
- Squads with overlapping files (>30%) MUST NOT run in parallel.
- Every squad follows the full standard flow. No shortcuts.
- The Maestro is NEVER part of a squad. It coordinates between them.
- Cross-squad communication always goes through the Maestro. Squads never talk to each other directly.
- If a squad blocks on a cross-squad dependency for more than 2 steps, Maestro merges the squads into one.
