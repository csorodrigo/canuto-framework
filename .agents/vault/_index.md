---
title: Canuto Framework — Vault Index
tags:
  - moc
  - index
aliases:
  - Home
  - Index
---

# Canuto Framework — Vault

> [!info] Map of Content
> This is the entry point for the Canuto Framework's Obsidian-native memory system.

## Memory Areas

### [[sessions/|Sessions]]
Daily session notes. Each session records goals, work done, decisions, and pending items.

### [[decisions/|Decisions]]
Architectural and business decisions. Each decision is a standalone note with context, reasoning, and trade-offs.

### [[instincts/|Instincts]]
Learned patterns from project experience. Confidence grows with repeated observation (low → medium → high).

### [[pending/|Pending Tasks]]
Tasks deferred from previous sessions. Prioritized and tracked until completion.

### [[audit/|Audit Log]]
Immutable record of significant session events (handoffs, gates, rework, escalations).

### [[metrics/|Metrics]]
Quality, velocity, and compliance metrics per session.

### [[design/|Design]]
Visual identity ([[design/profile|Design Profile]]) and [[design/components/|Component Inventory]].

## Visual Maps

### [[canvas/persona-flow.canvas|Persona Flow]]
Visual flow: Maestro → Architect → Coder → Tester → Reviewer.

### [[canvas/memory-map.canvas|Memory Map]]
How memory types connect: sessions → decisions → instincts.

## Database Views

### [[bases/instincts-by-confidence.base|Instincts by Confidence]]
Instincts grouped by confidence level (high → medium → low).

### [[bases/decisions-timeline.base|Decisions Timeline]]
All decisions in chronological order.

### [[bases/pending-tasks.base|Pending Tasks]]
Active tasks ordered by priority.

### [[bases/audit-by-type.base|Audit by Type]]
Audit events grouped by event type.

### [[bases/metrics-dashboard.base|Metrics Dashboard]]
Session metrics with summaries and trends.

### [[bases/components-registry.base|Components Registry]]
UI components by source type.

---

> [!tip] MCP Integration
> This vault is accessed by the Canuto Framework via the `obsidian-mcp-server`.
> See `.agents/mcp/setup.md` for configuration instructions.
