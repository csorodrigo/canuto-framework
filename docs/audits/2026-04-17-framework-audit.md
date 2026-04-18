# Canuto Framework Audit — Delta Report 2026-04-17

**Baseline**: 2026-04-15 audit (`.context/audits/canuto-session-audit-20260415/`)
**Final**: 2026-04-17 audit (`.context/audits/canuto-session-audit-20260417-final/`)

## Executive summary

Five refactors landed across the cross-project audit infrastructure, one surgical workspace migration, and a batch install sweep across 8 target projects. The combined effect is a more honest audit signal and an active-install footprint on the dormant/pre-v1.8 tail.

## Key metrics

| Metric | Baseline (04-15) | Final (04-17) | Δ |
|---|---:|---:|---:|
| Projects in inventory | 25 | 27 | +2 (new workspaces surfaced) |
| Sessions analyzed | 638 | 882 | +244 |
| Sessions with skill breakage | 189 (30%) | 11 (1.2%) | **−94%** |
| `pending_sync` flags | 158 | 33 | **−79%** |
| `offline_sync` flags | 123 | 123 | 0 (real markers preserved) |
| Slug collision projects | 1 | 3* | +2 |

\* The 3 final-state collisions are all `canuto-framework-v1` slug. Two are new CLAUDE.md files that `install.sh` created during Phase 1d from its default template. These were fixed surgically outside the framework repo (same pattern as rota_omie in Phase 1f).

## Bucket distribution (5-bucket taxonomy)

| Bucket | Baseline | Final | Notes |
|---|---:|---:|---|
| `healthy` | — (old `healthy` = 1) | 1 | `plomes-route-optimizer` |
| `v1.8-failing` | — (old taxonomy) | 6 | Tools present, capture still partial/failing. Active projects that benefit most from hook reinstall |
| `pre-v1.8` | (part of old `failing`) | 4 | Vault-only projects; no workspace install path |
| `dormant` | (part of old `failing`) | 4 | >30d since last session |
| `never-installed` | (part of old `failing`) | 12 | Projects with zero canuto bootstrap or inventory-only listings |

## What landed

### Audit infrastructure
- **5-bucket classifier** (`never-installed` / `dormant` / `pre-v1.8` / `v1.8-failing` / `healthy`) with deterministic first-match rules, symmetric install-signal check, and project-level triage ordering.
- **Heuristic tightening**:
  - `detectSkillBreakages`: replaced whole-blob substring match (`text.includes('skill') && text.includes('missing')`) with line-scoped regex requiring concrete error phrasing plus `.agents/skills/` path or a named skill id. Accepts flat and directory layouts, both error/path orders. Removed ambiguous `skill-missing` category.
  - `detectProbableSkillMatches`: threshold raised from 2 to 4; project-level dedup (skill miss no longer counts if the skill was read in *any* analyzed session of the project).
  - `pending_sync` now derives from `pending_count > 0` in vault parsers and a tight context regex in Codex logs.
  - `offline_sync` now reads audit frontmatter `event: OFFLINE_SYNC` authoritatively; filename detection scoped to `type: audit-event` entries only.
- **Field rename** for v1.8 tool detection: `session_capture_present → session_save_hook_present`, `obsidian_healthcheck_present → health_check_tool_present`. Audit now probes the real filenames (`.agents/hooks/session-save.sh`, `.agents/tools/codex-health-check.sh`). Backward-compat aliases preserved for one release.

### Operational fixes
- **rota_omie migration** (Phase 1f, outside the framework repo): CLAUDE.md slug corrected from `canuto-framework-v1` → `rota_omie`, `.context.md` rewritten with actual project metadata, local `.agents/vault` copied to `~/.canuto/vault/projects/rota_omie/`, `project-index.json` generated from git remote + `package.json`.
- **Batch install sweep** (Phase 1d): `install.sh --repair` on 5 `v1.8-failing` active workspaces (florence, lcd prague, minnetonka-v1, richmond, rota_omie) and `install.sh --update` on 3 reactivate targets (jakarta, ifood-raspador, video-produtividade). All 8 exited 0.
- **Residual collisions** after Phase 1d (ifood-raspador, video-produtividade): CLAUDE.md template pollution fixed inline.

### Skill discovery sharpening
- `context-maintenance`, `codex-github-ops`, `codex-browser-qa`, `codex-pr-writer`: trigger keywords broadened, evals extended from ~3 to 8 entries each. FEATURE-MAP.md surfaced these four skills explicitly.

## Forensic findings (no code change needed)

- `pending_sync` semantics: of 33 flagged sessions, 22 are natural "ended-with-pending-work" state (pending_count > 0 in session frontmatter) and 11 are residual noise from framework source mentions. The `.agents/.cache/pending-sync/` directories are empty on the top-flagged projects. No queue is broken. Full analysis at `.context/audits/phase-1e-pending-sync/findings.md`.
- 504 `co-review` "misses" in the baseline report were ~98% heuristic noise — 257 probable matches vs 5 actually-read sessions. Fixed at source by the heuristic tightening in Phase 1c.
- `session-capture.sh` and `obsidian-healthcheck.sh` were planned tool names in the baseline audit but don't exist in the framework; real v1.8 tools are `session-save.sh` and `codex-health-check.sh`. Corrected by the Phase 1c.2 rename.

## Known follow-ups

1. **install.sh template pollution**: the default CLAUDE.md template hardcodes `project-slug: canuto-framework-v1`, so every fresh install regresses to the canuto slug. The surgical fixes are per-project. A framework-level guard (slug validation + warning in `canuto_project_slug`, or template placeholder) remains open.
2. **install.sh self-refresh contamination**: running `install.sh` with absolute path from another project can re-exec the remote installer and pull in drift across unrelated framework files. Workspace was restored; a tighter `should_refresh_installer` guard would prevent it next time.
3. **Phase 2 gate residuals**: `healthy` bucket is still 1 (target was ≥ 4). The 6 `v1.8-failing` projects have v1.8 tools but low capture — fixing capture requires actual session activity + vault writeback, which this PR didn't force.
4. **pending_sync threshold**: current bucket rule (`pendingSyncOrphanRatio > 0.20`) remains but no project hits it after normalization. Threshold is inert for now.

## Commit list (this PR)

| Commit | Phase | Summary |
|---|---|---|
| `b04fd2d` | 0 Governance | Audit tool baseline + cost dashboard |
| `151c245` | 1a Classifier | 5-bucket project taxonomy |
| `d44da79` | 1b Triagem | Dormant triage decisions (`.agents/data/project-status-overrides.json`) |
| `e218ba7` | 1c Heurística | Tightened skill-breakage and probable-match detectors |
| `7a87859` | 1e Sync detector | Tightened pending_sync and offline_sync detection |
| `7a247f3` | 1c.2 Tool names | Audit probes real v1.8 tool names |
| `2afa417` | 3 Skill discovery | Sharpen trigger keywords on 4 top-missed skills |

## Validation

- `bash test-framework.sh` → 124 passed
- `node --test .agents/tools/framework-session-audit.test.js` → 41 passed
- Final audit regenerated and compared; delta matches the numbers above
- All review rounds passed (7.5 / 8.4 / 7.8 / 8.2 overall)

