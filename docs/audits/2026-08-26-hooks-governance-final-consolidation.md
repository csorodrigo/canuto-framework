# Hooks governance — final consolidation receipt

Date: 2026-08-26

This change closes the remaining T4/T5 runtime overlap identified in the ticket audit. The managed Claude retirement manifest now removes the legacy host-pressure, secret-hygiene, process-self-match, protected-read, prompt-secret, raw-command-log, and delivery-proof registrations. The Codex retirement manifest removes the four corresponding machine gates. `log-commands.sh` is no longer shipped or registered; delivery proof is no longer a local-only managed handler.

The shared repository-policy source remains the single evaluator. `CU-60` is an advisory `UserPromptSubmit` entrypoint whose small wrapper delegates to the same `repo-policy-hook.mjs` evaluator, with a distinct installed command target. This preserves the reconciler's one-command/one-registration invariant while avoiding a second evaluator.

The active `CU-08` observer now emits only one-way SHA-256 digests for observed command/path values. The event log uses `cmd_sha256` and `file_sha256`; no raw command or path is serialized into OTLP or event-log payloads.

Evidence:

- `node --test .agents/hooks/reconcile-hooks.test.mjs .agents/hooks/retirement-t7.test.mjs`: 90 passed, 0 failed.
- Claude live read-only plan removes `CU-13`, `CU-16`, `CU-17`, `CU-19`, `CU-24`, `CU-57`, `CU-20`, and `CU-41`; external registration count remains 31.
- Codex live read-only plan removes `CX-05`, `CX-06`, `CX-07`, and `CX-08`; external registration count remains 9.
- Core live read-only plan adds `CU-60` and updates the shared policy source; no raw command logger is reintroduced.
- T8 external-owner behavioral receipt: `.agents/hooks/audit/t8-behavioral-canary-receipt.json`.

The live plans are intentionally not applied from this branch: publication and exact-SHA installation are separate T9/T10 actions performed only after this commit is merged and refs are CI-green.
