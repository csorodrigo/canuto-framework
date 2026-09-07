# Canuto Framework v1.9 Summary

Canuto is a multi-agent operating framework for AI-assisted software work. It
shares one operational contract across Claude and Codex, preserves project WIP,
uses an Obsidian-native two-tier memory, and records lifecycle evidence in an
append-only event log.

## Runtime flow

```text
Maestro → Architect → Coder → Reviewer
                  ↘ /test or /fix when deeper validation is needed
```

The active personas are Maestro, Architect, Coder, Reviewer, Contextualizer, and
Investigator. Tester and Debugger remain archived; their workflows are covered
by explicit test/fix paths rather than always-loaded personas.

## v1.9 operational guarantees

- Substantial work advances through three to seven verifiable milestones. The
  root reports a textual progress bar only when evidence advances and continues
  automatically after intermediate updates.
- `run-ledger.sh` records only the milestone labels supplied to it; it does not
  capture prompts or the surrounding process environment automatically. Labels
  must remain non-sensitive because they are persisted literally.
- Bounded read-only leaves use the smallest compatible configured profile;
  substantial changes, releases, and rollouts receive one independent
  adversarial review per fixed point and question.

- Distributed defaults contain no machine-specific projects, users, hosts, or
  workspace paths. Effective Skill Gardener configuration belongs only to the
  local machine and valid local bytes are preserved.
- `--yes` confirms operational prompts but never authorizes staging or commit.
  Only `--commit` can create a framework commit, and it uses declared paths
  without absorbing unrelated staging.
- `stable` is the default distribution channel; `main` is explicit edge.
  Version, release-ref, exact-SHA pinning, and rollback are supported.
- Install/update publish deterministic source receipts. The multi-project updater
  verifies complete content before reporting a consumer as current.
- The final release gate runs on Ubuntu and macOS with `/bin/bash`, plus two
  distinct consumer fixtures including a path with spaces and different rendered
  `CODEX.md` outputs.

## Memory and evidence

- Hypothesis tier: sessions, metrics, pending tasks, and low-confidence instinct
  candidates may be written mechanically.
- Curated tier: decisions and promoted instincts require explicit human approval.
- `events/log.jsonl` is the session-event source of truth; notes and dashboards
  are projections.
- Code, test, commit, push, PR, merge, deploy, and runtime health remain separate
  states with separate receipts.

## Release usage

```bash
bash install.sh --update                    # stable
bash install.sh --update --channel edge     # main
bash install.sh --update --version 1.9.0    # pinned release
bash install.sh --update --ref <commit-sha> # exact pin
bash install.sh --rollback <version>        # rollback
```

Promotion and rollback policy: [`docs/RELEASE-PROMOTION.md`](docs/RELEASE-PROMOTION.md).
