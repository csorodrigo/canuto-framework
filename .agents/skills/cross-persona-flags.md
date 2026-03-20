shortDescription: Personas emit flags suggesting which other persona should investigate a discovered concern.
usedBy: [maestro, architect, coder, tester, debugger, reviewer]
version: 1.0.0
lastUpdated: 2026-03-18
copyright: Rodrigo Canuto © 2026.
inspiration: pgs-engine — outbound flags enable cross-partition awareness despite isolation.

## When to Use

**Triggers:**
- Any persona discovers something outside their scope that another persona should know about
- Coder notices a testable edge case → flag for Tester
- Tester finds a design inconsistency → flag for Reviewer
- Architect spots a security concern → flag for Coder (via security-practices skill)
- Debugger identifies a pattern that could affect other areas → flag for Architect

**Not for:**
- Escalations (use the existing escalation protocol for blocking issues)
- Normal handoff information (goal, constraints, paths — that's the handoff protocol)

---

## Purpose

Today, Maestro decides all routing alone. Cross-persona flags let individual personas contribute intelligence about what needs attention elsewhere — enabling **lateral discovery** between personas that don't normally interact directly.

This is analogous to how PGS Engine's partitions emit "outbound flags" suggesting adjacent partitions to consult, enriching the synthesis phase.

---

## Concepts

### Outbound Flag

A non-blocking suggestion from one persona to another, routed through Maestro:

```
[FLAG → Tester] Edge case discovered: empty cart checkout is not guarded in src/api/cart.ts:47
```

### Flag Priority

| Priority | Meaning | Maestro Action |
|----------|---------|----------------|
| `info` | Awareness only — may be useful | Log, surface at session end |
| `suggest` | Should be checked when convenient | Queue for next relevant handoff |
| `urgent` | Likely impacts current task quality | Route immediately |

---

## Procedure

### For Personas (Emitting Flags)

Add an `## Outbound Flags` section to any handoff where cross-persona concerns were discovered:

```markdown
## Outbound Flags

- [FLAG → Tester | suggest] Empty cart checkout path not guarded — src/api/cart.ts:47
- [FLAG → Reviewer | info] New utility function duplicates logic in src/utils/format.ts — consider consolidation
- [FLAG → Architect | urgent] External payment API has no retry logic — may need plan revision
```

**Rules:**
1. Specify the target persona
2. Assign priority: `info`, `suggest`, or `urgent`
3. Include the specific location or context
4. Keep each flag to one line
5. Maximum 5 flags per handoff (focus on the most impactful)

### For Maestro (Processing Flags)

When receiving a handoff with outbound flags:

1. **Urgent flags** → evaluate immediately. If valid, adjust routing or re-plan.
2. **Suggest flags** → queue and include in the next handoff to the target persona:
   ```
   [Maestro → Tester] Testing the checkout flow.
   Goal: Verify edge cases in cart and payment.

   Cross-persona flags to investigate:
   - [from Coder] Empty cart checkout path not guarded — src/api/cart.ts:47
   ```
3. **Info flags** → log and surface in the session summary if still relevant.
4. **Track flag resolution** — when the target persona addresses a flag, note it as resolved.

### Flag Resolution

Target persona acknowledges the flag in their handoff:

```markdown
## Flag Resolution

- [RESOLVED] Flag from Coder re: empty cart checkout → Added guard clause and test. See src/api/cart.ts:47.
- [DISMISSED] Flag from Coder re: utility duplication → Checked: functions have different semantics, not duplicated.
```

---

## Examples

### ✅ Good — specific, actionable flag with clear target

```markdown
## Outbound Flags

- [FLAG → Tester | suggest] Race condition possible: concurrent cart updates don't use optimistic locking — src/api/cart.ts:82
- [FLAG → Reviewer | info] Created 3 new utility functions in src/utils/ — may benefit from a consolidation review
```

### ✅ Good — Maestro routing a flag to target persona

```
[Maestro → Tester] Testing the user dashboard feature.
Goal: Cover edge cases and error states.

Cross-persona flags to investigate:
- [from Architect | suggest] Dashboard loads user preferences — verify behavior when preferences are null (new user)
- [from Coder | suggest] Chart component receives empty data array — check rendering with 0 data points
```

### ❌ Bad — vague, no target, no priority

```markdown
## Outbound Flags

- Something might be wrong with the database
- Tests should probably check more things
```

This is bad because: no target persona, no priority, no specific location — Maestro can't route or act on this.

### ❌ Bad — using flags for escalations

```markdown
## Outbound Flags

- [FLAG → Maestro | urgent] Build is broken, can't continue
```

This is bad because: blocking issues use the **escalation protocol**, not flags. Flags are for non-blocking cross-persona awareness.

---

## Guardrails

- **Flags are suggestions, not commands.** The target persona evaluates and may dismiss.
- **Maximum 5 flags per handoff.** Prioritize the most impactful.
- **Don't use flags for blocking issues.** Those are escalations to Maestro.
- **Don't flag things already in the plan.** Only flag discoveries not previously identified.
- **Maestro is the router.** Personas never communicate directly — all flags go through Maestro.
- **Dismissed flags are valid.** Not every flag leads to action. The value is in the awareness.
