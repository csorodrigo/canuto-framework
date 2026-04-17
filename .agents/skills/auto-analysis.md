---
skill: auto-analysis
shortDescription: Deep project scan plus cross-project vault intelligence that generates project indexes and onboarding reports.
trigger: /auto-analysis
persona: maestro
version: 1.1.0
lastUpdated: 2026-03-23
evals:
  - prompt: "just installed the framework on this project, run the auto analysis"
    should_trigger: true
  - prompt: "project-index.json hasnt been updated in weeks, refresh it"
    should_trigger: true
  - prompt: "show me the onboarding report for this project"
    should_trigger: false
  - prompt: "analyze this specific file for code quality issues"
    should_trigger: false
---

# Auto-Analysis — Cross-Project Intelligence

Generates a `project-index.json` (deep scan of the current project) and an `onboarding-report.md` (cross-referencing with all other indexed projects in the vault).

---

## When to Use

- **Automatically**: Offered after `install.sh --install` or `--migrate`
- **On demand**: User runs `/auto-analysis` at any time
- **Periodic refresh**: When `project-index.json` is older than 30 days

---

## What It Does

### Phase 1: Deep Project Scan → `project-index.json`

Scans the current project directory and generates a rich index at `~/.canuto/vault/projects/{slug}/project-index.json`:

- **Stack detection**: Language, framework, ORM, test framework, bundler, package manager
- **Full dependency parsing**: All production and development dependencies with versions
- **Structure analysis**: Entry points, source/test/config directories, LOC counts, file counts
- **Domain detection**: Groups files by domain (auth, api, data, payments, etc.) with confidence scores
- **Pattern detection**: Identifies architectural patterns (middleware-chain, repository-pattern, service-layer, etc.)
- **CI/CD analysis**: Provider, workflows, lint/test/deploy steps
- **Environment variables**: From `.env.example` files and source code scanning
- **API surface**: Route count, middleware count, model count

### Phase 2: Cross-Reference → `onboarding-report.md`

Compares the current project against all other indexed projects in the vault:

- **Stack match %**: Shared dependencies / total dependencies
- **Domain match %**: Shared domains / total domains
- **Pattern match %**: Shared architectural patterns
- **Overall match**: Weighted average (50% deps, 30% domains, 20% patterns)

For similar projects (match > 40%), collects:
- High and medium confidence instincts → recommendations
- Decisions in matching domains → relevant decisions
- Session rework patterns → common issues to watch for
- Global instincts → always included

Output: `~/.canuto/vault/projects/{slug}/onboarding-report.md`

---

## Procedure

1. Verify `python3` is available
2. Run the analysis (calls `post_install_analysis()` from install.sh logic, or equivalent inline Python)
3. Present summary to user:

```
Auto-Analysis Complete:
- Project: {slug} ({language}/{framework})
- Indexed: {file_count} files, {loc} LOC, {domain_count} domains
- Similar projects: {match_count} (best match: {best_slug} at {match}%)
- Recommended instincts: {instinct_count}
- Relevant decisions: {decision_count}
- Report saved: ~/.canuto/vault/projects/{slug}/onboarding-report.md
```

4. Offer to show the full report or specific sections

---

## Standalone Script

The cross-reference can also be run as a standalone script for all projects at once:

```bash
bash cross-reference.sh                  # Full analysis
bash cross-reference.sh --project slug   # Focus on one project
bash cross-reference.sh --terminal       # Terminal output only
```

This generates `~/.canuto/vault/reports/cross-reference-YYYY-MM-DD.md` with:
- Stack clusters (projects grouped by language/framework)
- Shared dependencies across projects
- Cross-project instinct patterns
- Solution transfer opportunities
- Decision domain map

---

## Notes

- The `project-index.json` does NOT require Claude/LLM — it's pure static analysis (Python)
- The scan is fast (~5-15 seconds per project depending on size)
- Re-running updates the index in place (idempotent)
- Projects without `project-index.json` are excluded from cross-referencing
- To index a new project: run `install.sh --install` (with auto-analysis) or `/auto-analysis`
