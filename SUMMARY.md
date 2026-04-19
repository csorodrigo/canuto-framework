# Canuto Framework v1.6 Summary

Canuto is a personal multi-agent framework for AI-assisted software work. It gives a project a stable `.agents/` structure with personas, skills, local memory, and a `CLAUDE.md` operating contract so every session starts with context and ends with reusable learning.

## What This Release Adds

This release keeps the v1.6 Obsidian-native runtime and adds a sharper learning-loop layer:

- Project diagnosis before risky work.
- Rework detection before repeating failed approaches.
- Session-end learning for summaries, pending tasks, decisions, metrics, and candidate instincts.
- Pending triage so backlog memory stays usable.
- Safe Obsidian/Canuto vault write-back preview before any external memory write.
- Optional domain QA skills for dashboards, scrapers, routing, spreadsheets, and frontend visual checks.

## Default Flow

1. Maestro reads project setup, memory, and context.
2. Maestro detects project style: `Canuto`, `foreign-schema`, or `new`.
3. Architect turns the goal into a plan.
4. Coder implements the change.
5. Tester validates behavior and edge cases.
6. Debugger investigates failures when tests or checks fail.
7. Reviewer checks quality, risk, tests, and PR description.
8. Maestro closes the session with learning and memory updates.

## Passive Skills

Passive skills are called by the framework lifecycle or by evidence in the current session. They are not background daemons and they are not silent.

| Skill | Trigger |
|------|---------|
| `canuto-project-doctor` | Session start when setup, memory, or context looks suspicious. |
| `canuto-rework-detector` | Retry loops, repeated review fixes, repeated test failures, stale context, dirty-state, or repeated pending tasks. |
| `canuto-session-end-learning` | End of session before final handoff. |
| `canuto-pending-triage` | Duplicated, vague, stale, or oversized pending backlog. |
| `obsidian-writeback-queue` | Proposed write-back to Obsidian or the Canuto vault. |

## Active Skills

Active skills are selected by domain, installed on demand, or requested directly by the user.

| Skill | Best For |
|------|----------|
| `dashboard-regression-guard` | BI, admin, analytics, and reporting dashboards. |
| `scraper-resilience` | Scrapers, collectors, parsers, and fragile data extraction. |
| `route-optimizer-qa` | Routing, geocoding, logistics, and delivery sequencing. |
| `spreadsheet-delivery-check` | XLSX, CSV, exports, and spreadsheet deliverables. |
| `frontend-visual-qa` | Web apps, landing pages, interactive UIs, and games. |

## Memory Policy

Canonical project memory lives in the Obsidian-native Canuto vault:

- `projects/{project-slug}/sessions/`: session summaries and outcomes.
- `projects/{project-slug}/pending/`: actionable unfinished tasks.
- `projects/{project-slug}/decisions/`: decisions future sessions must respect.
- `projects/{project-slug}/metrics/`: session quality and rework metrics.
- `projects/{project-slug}/instincts/`: reusable lessons promoted by the learning loop.

`obsidian-writeback-queue` previews the target, action, summary, and risk before non-standard writes or external write-back operations.

## Rollout Rule

After this branch is merged into GitHub `main`, update projects with:

```bash
bash install.sh --update
```

For projects without a local installer copy, run:

```bash
curl -fsSL https://raw.githubusercontent.com/csorodrigo/canuto-framework/main/install.sh | bash -s -- --update
```
