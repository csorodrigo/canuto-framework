# Native Orchestration — Quarantine Bundle

Status: **non-distributed, non-discovered, non-installed**.

This directory contains a candidate Codex-native orchestration overlay for adversarial evaluation. It is deliberately outside `.agents/skills/` and the repository-root `.codex/agents/` because those locations are active runtime surfaces. Placing the candidate there would make it part of the framework distribution contract before its behavior is proven.

## Why this is quarantined

Canuto already has one orchestration plane:

- Maestro owns decomposition, approvals, routing, synthesis, verification, and closeout;
- `.agents/config/models.yaml` is the canonical model/effort source;
- `~/.codex/bin/codex-delegate.sh` is the canonical mutable tier-2 path;
- `adaptive-routing`, `co-review`, governance, event-log, budget controls, and verification gates already cover adjacent responsibilities.

The original integration proposal added native writers, model pins, and a second hook plane. The adversarial review found that this could create split-brain routing, parallel writer collisions, duplicate events, and configuration drift. The candidate therefore permits only explicit, terminal, read-only leaves.

## Layout

```text
.agents/experiments/native-orchestration/
├── README.md
├── validate.sh
└── candidate/
    ├── .agents/skills/native-orchestration/
    │   ├── SKILL.md
    │   ├── agents/openai.yaml
    │   ├── evals/cases.yaml
    │   └── references/
    └── .codex/agents/
        ├── canuto_native_scout.toml
        └── canuto_native_reviewer.toml
```

The `candidate/` tree mirrors the paths that a future promoted version would use. It is inert while it remains below this experiment directory.

## Static validation

```bash
bash .agents/experiments/native-orchestration/validate.sh
```

The validator fails if:

- an active root skill or agent copy exists;
- implicit invocation is enabled;
- either leaf is not `read-only`;
- a leaf pins model or reasoning effort outside canonical routing;
- a mutable/escalation native persona appears;
- recursive delegation is not explicitly prohibited.

## Disposable behavioral trial

Use only a throwaway worktree or disposable clone. Never stage this candidate into a live consumer repository.

```bash
trial=/tmp/canuto-native-orchestration-trial
rm -rf "$trial"
git worktree add --detach "$trial" HEAD

mkdir -p \
  "$trial/.agents/skills" \
  "$trial/.codex/agents"

cp -R \
  .agents/experiments/native-orchestration/candidate/.agents/skills/native-orchestration \
  "$trial/.agents/skills/native-orchestration"

cp \
  .agents/experiments/native-orchestration/candidate/.codex/agents/*.toml \
  "$trial/.codex/agents/"
```

Run explicit `$native-orchestration` cases from `candidate/.agents/skills/native-orchestration/evals/cases.yaml`, capture the actual agent graph and outputs, then remove the worktree.

## Promotion gate

Promotion is a separate reviewed change and must include all of the following:

1. Behavioral eval evidence from the current Codex Desktop/CLI runtime.
2. Zero native mutation attempts and zero nested delegation attempts.
3. Evidence that the overlay adds value beyond `co-review` and direct Maestro work.
4. Measured spawn overhead, timeout rate, and useful-finding rate.
5. Installer distribution entries for every promoted skill/reference file and both project agents.
6. Root-suite coverage proving install, update, check, consumer E2E, and rollback behavior.
7. Registry and routing documentation updates.
8. `allow_implicit_invocation: false` retained for the first promoted release.

Do not combine promotion with implicit activation, new hooks, native writers, or live installation.
