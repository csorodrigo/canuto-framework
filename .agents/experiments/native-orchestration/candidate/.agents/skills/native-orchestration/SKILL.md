---
name: native-orchestration
description: >
  Use only when explicitly invoked in the direct Codex runtime to coordinate at
  most two independent, read-only native subagents for evidence gathering or
  blind review on M/L or otherwise high-risk work. Do not use for implementation,
  small or sequential tasks, overlapping ownership, autonomous execution, or to
  bypass the Canuto Maestro, canonical model routing, wrapper-based mutation,
  approval gates, or verification gates.
shortDescription: Explicit Codex-native read-only orchestration overlay in quarantine.
usedBy: [maestro]
version: 0.1.0
lastUpdated: 2026-08-24
status: quarantine
runtime: codex
evals:
  - prompt: "Use $native-orchestration to map two independent failure surfaces before we choose a fix."
    should_trigger: true
  - prompt: "Use $native-orchestration for an independent Standards and Spec review of this approved M plan."
    should_trigger: true
  - prompt: "Fix this typo with parallel agents."
    should_trigger: false
  - prompt: "Spawn two workers to edit the same files."
    should_trigger: false
  - prompt: "Deploy this automatically after the agents finish."
    should_trigger: false
---

# Native Orchestration

## Purpose

Add a narrow Codex-native execution option without creating a second orchestrator.
The Canuto **Maestro remains the root owner** of decomposition, user communication,
approvals, routing, synthesis, mutation, verification, and final claims.

This skill is a quarantine overlay for one capability only:

> Run a small number of independent, read-only native Codex leaves when keeping
> their exploration or review context outside the root thread materially improves
> evidence quality.

It does **not** replace or supersede:

- `.agents/personas/maestro.md`;
- `.agents/config/models.yaml`;
- `.agents/skills/adaptive-routing/`;
- `.agents/skills/co-review/`;
- `.agents/skills/cost-routing.md`;
- `.agents/skills/governance.md`;
- `.agents/skills/verification-gates.md`;
- `~/.codex/bin/codex-delegate.sh` for mutable tier-2 work;
- the event log, audit trail, rework detection, or closeout flow.

When any rule conflicts, the existing Canuto source of truth wins.

## Activation Gate

All conditions below must hold:

1. The skill was explicitly invoked as `$native-orchestration`.
2. The current runtime is direct Codex, not the Claude Maestro runtime.
3. The task is M/L **or** has material production, security, payment, data,
   release, or specification risk.
4. There are at least two independently answerable read-only questions, or one
   bounded question that benefits from an isolated blind review.
5. Each leaf has a concrete evidence or review deliverable.
6. No human approval is being assumed, simulated, or bypassed.
7. The expected benefit exceeds the spawn, context, and synthesis overhead.

If any condition fails, stay single-agent or use the existing canonical flow.

## Do Not Use

Do not activate this skill for:

- XS/S work where the root can inspect directly;
- a task whose next step depends immediately on the previous step;
- implementation, test repair, migration, deployment, publication, or external
  communication;
- multiple agents that would need to mutate the same checkout;
- requests to "keep going" without an approved plan or required human decision;
- work where no authoritative source, reproduction, test, or review criterion
  exists;
- a second opinion already covered by `co-review` without a distinct reason;
- broad brainstorming whose output has no decision contract;
- recursive delegation or agent-created agents.

## Sources of Truth

Use these in precedence order:

1. User request and explicitly approved decisions.
2. Repository governance and project instructions.
3. `.agents/personas/maestro.md`.
4. `.agents/config/models.yaml` for model, effort, timeout, and sandbox routing.
5. Existing Canuto skills and gates.
6. This skill.

This skill never pins model names or reasoning effort. Custom native agent files
also omit those fields. The root may pass an explicit model or effort only after
resolving the current canonical role from `.agents/config/models.yaml`; otherwise,
inheriting the runtime default is safer than creating a competing source of truth.

## Allowed Native Agents

Quarantine permits exactly two project-scoped leaves:

- `canuto_native_scout`: read-only evidence collection.
- `canuto_native_reviewer`: read-only independent review.

Both are defined in `.codex/agents/`, run with `sandbox_mode = "read-only"`, and
must never delegate.

There is deliberately no native worker, coder, deployer, or critic in v0.1.0.
Mutation remains in the established Coder / `codex-delegate.sh` path so that the
existing timeout, sandbox, artifact, metrics, approval, and verification controls
remain effective.

## Concurrency and Depth

- Maximum native leaves per wave: **2**.
- Maximum native delegation depth: **1** by contract.
- Maximum mutable agents per checkout: **0** under this skill.
- Never launch a second wave before the root has consumed and reconciled the
  first wave.
- Never use thread capacity as a target. One leaf is preferred when one leaf is
  enough.

The runtime may expose a larger global thread cap. This skill does not consume it
merely because it exists.

## Execution Protocol

### Phase 0 — Preflight

Before spawning anything, the root must state internally or in the task record:

- why delegation is better than direct inspection;
- the independent questions;
- the authoritative sources available;
- the approval boundary;
- the maximum number of leaves;
- the stop condition.

If independence is unclear, do not spawn.

### Phase 1 — Assignment Design

Create one assignment per leaf using
`references/assignment-contract.md`. Every assignment must include:

- `TASK_ID`;
- `ROLE`;
- `OBJECTIVE`;
- `QUESTION`;
- `READ_SET`;
- `FORBIDDEN_SET`;
- `SOURCE_OF_TRUTH`;
- `CONSTRAINTS`;
- `VALIDATION_OR_EVIDENCE_STANDARD`;
- `RETURN_SCHEMA`;
- `MUTATION_POLICY: read-only`;
- `DELEGATION_POLICY: leaf-never-delegate`;
- `STOP_CONDITION`.

Do not forward the entire conversation. Send only the minimum source material and
paths needed to answer the assigned question.

### Phase 2 — Read-Only Wave

Spawn one or two leaves:

- Use `canuto_native_scout` for locating facts, mapping code paths, reproducing a
  failure without mutation, or comparing authoritative artifacts.
- Use `canuto_native_reviewer` for an independent plan/diff/design review with a
  named axis and source of truth.

Parallelism is allowed only when the assignments are independent. If leaf B needs
leaf A's result, run them sequentially.

### Phase 3 — Root Reconciliation Gate

The root must inspect each result against `references/result-contract.md` and
classify it as:

- `ACCEPTED` — complete and evidence-backed;
- `PARTIAL` — useful but missing declared evidence;
- `CONFLICTING` — disagrees with another result or authoritative source;
- `REJECTED` — out of scope, unsupported, or contract-breaking.

The root must not average conflicting conclusions. Reopen the underlying source,
run a discriminating check, or declare the uncertainty.

### Phase 4 — Canonical Mutation Path

If evidence supports a change and all required approvals exist:

1. Return to the standard Maestro sizing and routing flow.
2. Create the canonical task file with the approved plan, files, constraints,
   acceptance criteria, and relevant evidence.
3. Delegate mutable M/L work through
   `~/.codex/bin/codex-delegate.sh <role> <task-file> <out-file>`.
4. Preserve the one-writer-per-checkout rule.

This skill itself performs no mutation and authorizes none.

### Phase 5 — Independent Review

After mutation, the root may invoke one `canuto_native_reviewer` leaf when the
review is genuinely independent from existing `co-review` coverage. Name the
axis explicitly:

- `Standards` — repository correctness, security, maintainability, regressions;
- `Spec` — fidelity to the original request and approved plan;
- a bounded risk axis such as `migration safety` or `payment invariants`.

Do not claim execution validation from a read-only reviewer. Tests and live-state
claims still require the canonical verification gates.

### Phase 6 — Authoritative Final Verification

Before claiming fixed, merged, deployed, published, paid, migrated, delivered, or
complete, the root must reopen or rerun the authoritative source of truth. Agent
reports are evidence inputs, not final state.

Record material delegation, conflicts, approvals, validation, and residual risk in
the existing event-log / closeout flow.

## Failure Handling

### Leaf fails or times out

- Do not silently respawn.
- Inspect any partial result once.
- Decide whether direct inspection is cheaper than another spawn.
- At most one focused retry may be authorized by the root.
- Never convert a failed read-only leaf into a mutable leaf.

### Leaf violates scope

Reject the result, record the violation, and continue without trusting unsupported
claims. Do not broaden the task merely because a leaf explored adjacent areas.

### Results disagree

State the conflicting hypotheses and run the smallest discriminating check against
the authoritative source. Escalate to the user only for a genuine decision, not a
fact that can be verified.

### Required approval is missing

Stop before mutation or external action. Record the precise pending decision.
Native delegation never supplies human consent.

## Adversarial Invariants

A valid execution must preserve all of these:

1. **One orchestrator:** Maestro remains final owner.
2. **One model-routing source:** `.agents/config/models.yaml` remains canonical.
3. **One mutable path:** writer work remains behind the existing wrapper and gates.
4. **No parallel writers:** native leaves are read-only.
5. **No recursive agents:** every native leaf is terminal.
6. **No implicit activation:** `allow_implicit_invocation` stays false in quarantine.
7. **No approval laundering:** agents cannot approve production or external action.
8. **No verification laundering:** an agent report is not a test or live-state proof.
9. **No context dumping:** assignments contain the minimum sufficient context.
10. **No forced parallelism:** use fewer leaves whenever possible.

Violation of any invariant is a hard stop for this skill.

## Promotion Criteria

Do not promote from quarantine or enable implicit invocation until real-task evals
show all of the following:

- zero native mutation attempts;
- zero nested delegation attempts;
- zero approval or verification violations;
- no regression in the canonical wrapper path;
- useful findings in a meaningful share of accepted runs;
- lower rework or better defect discovery than the single-agent baseline;
- acceptable spawn overhead and timeout rate;
- no duplicate coverage with `co-review` or `adaptive-routing`.

Promotion requires a separate reviewed change. It must not be bundled with this
initial quarantine introduction.
