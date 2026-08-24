# Adversarial Review of the Original Integration Plan

## Verdict

The original proposal had useful principles, but its implementation would have
created a second orchestration plane inside a framework that already has one.
This quarantine design keeps the useful read-only isolation and removes the main
sources of split-brain, writer collision, and configuration drift.

## Failure Modes Found

### Duplicate root authority

The Canuto Maestro already owns decomposition, delegation, approvals, synthesis,
and closeout. A broad `canuto-orchestrate` skill with its own routing policy could
produce two competing answers to "who decides next?".

**Correction:** this skill is a subordinate, explicit Codex-runtime overlay. Maestro
always remains root.

### Competing model configuration

The first proposal pinned Luna, Terra, and Sol inside custom agent TOMLs. Canuto
already declares `.agents/config/models.yaml` as the sole model/effort source, and
the wrapper parser depends on its exact layout.

**Correction:** native agent TOMLs omit model and effort entirely. No canonical
routing file is changed in quarantine.

### Parallel writer collision

Prompt-level `WRITE_SET` ownership is not a hard filesystem boundary. Two native
workspace-writing agents in the same checkout can still race, touch shared generated
files, or invalidate each other's assumptions.

**Correction:** v0.1.0 has no native writer. Native leaves are mechanically
read-only; mutation stays in the existing one-writer wrapper path.

### Duplicate hook plane

Canuto already has pre-tool guards, event logging, pre-finalize checks, governance,
and verification gates. New `PreToolUse`, `SubagentStop`, and `Stop` scripts would
introduce ordering, duplicate-event, installer-merge, and recovery risks.

**Correction:** add no hooks in quarantine. Observe real native-agent behavior first;
extend the existing hook plane only in a separate evidence-backed change.

### False confidence in hook enforcement

Agent start/stop callbacks are observability surfaces, not a complete security
boundary. A contract cannot depend on a callback that is incapable of blocking all
possible specialized tool paths.

**Correction:** use read-only sandbox plus prompt contract plus root verification;
do not claim exact write-set enforcement.

### Unbounded spawn and cost

The source skill's proactive "two separable jobs" trigger is too permissive for a
framework whose own audits found significant spawn overhead and timeout risk.

**Correction:** explicit invocation, M/L or material-risk gate, maximum two leaves,
and a requirement that expected evidence value exceed overhead.

### Recursive delegation without a runtime depth control

A reliable global `max_depth` control is not part of the current Canuto contract.
A leaf could otherwise become a coordinator and expand the graph unpredictably.

**Correction:** only terminal project agents are defined; nested delegation is a
hard contract violation. Promotion requires observed zero nested attempts.

### Split-brain between Claude and direct Codex runtimes

Canuto supports both Claude Maestro and direct Codex Maestro. Installing one global
native-agent policy across both would bypass the Claude runtime's wrapper-based
routing and cross-model review assumptions.

**Correction:** this skill is direct-Codex-only. Claude keeps the existing flow.

### Approval and verification laundering

Parallel agents can make unsupported completion claims sound consensual. Agreement
between agents is not human approval, test execution, or live-state proof.

**Correction:** approvals and final verification remain root-owned and tied to the
existing governance and verification gates.

## Quarantine Rollout

1. Introduce the explicit skill and two read-only project agents.
2. Run static validation and trigger evals.
3. Trial only on selected M/L investigations and independent reviews.
4. Compare defect discovery, rework, overhead, timeout, and contract violations
   against the single-agent baseline.
5. Decide separately whether any hook integration or native writer is justified.
6. Never combine promotion, implicit activation, and live installation in the same
   change.
