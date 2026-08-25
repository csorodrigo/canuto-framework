---
type: requirements
project: "{{title}}"
created: {{date:YYYY-MM-DD}}
last-updated: {{date:YYYY-MM-DD}}
status: draft
related-decisions: []
related-sessions: []
tags:
  - requirements
---

# Requirements: {{title}}

> **How to use:** Assign a REQ-ID to each requirement. IDs flow through the entire pipeline:
> Architect plan (steps list `Reqs:`) → Coder Implementation Summary (`### Requirements Delivered`) → Reviewer (coverage check).
> Keep IDs stable — never reuse a deleted ID.

## v1 — Must Have (current scope)

| ID | Requirement | Phase | Status |
|----|-------------|-------|--------|
| REQ-001 | <description> | planning | 🔲 open |
| REQ-002 | <description> | planning | 🔲 open |

## v2 — Should Have (future scope)

| ID | Requirement | Phase | Status |
|----|-------------|-------|--------|
| REQ-101 | <description> | — | 🔲 backlog |

## Status Legend

| Symbol | Meaning |
|--------|---------|
| 🔲 open | Not yet planned |
| 🟡 in-progress | Planned or being implemented |
| ✅ delivered | Implemented and verified |
| ❌ cut | Descoped |

## Change Log

| Date | Change |
|------|--------|
| {{date:YYYY-MM-DD}} | Initial draft |
