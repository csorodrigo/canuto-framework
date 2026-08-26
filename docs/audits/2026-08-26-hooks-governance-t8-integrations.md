# Hooks Governance T8 Integrations

Generated: 2026-08-26
Base: `f0254285c00929cbf3a3e1b2206777737fdc82f6`

## Implemented

- Canuto Claude lifecycle moved to plugin-owned manifests:
  `CU-38`, `CU-43`, `CU-45`, `CU-49`.
- Canuto Claude disabled manifest also retires legacy global registrations for
  `CU-38`, `CU-43`, `CU-45`, `CU-49`, so disabled means zero Canuto Claude
  execution from either old or plugin-owned commands.
- Canuto `CU-43` now uses real `PreCompact` instead of the old generic
  `Notification` heuristic registration.
- Browser QA screenshot counter moved to a plugin-owned manifest:
  `CU-32`.
- Browser QA state key includes repository, worktree and cwd identity in
  addition to `session_id`, preventing shared counters across repositories that
  reuse the same Claude session identifier.
- Obsidian cleanup is represented by opt-in Claude/Codex plugin manifests:
  `CU-48`, `CX-16`. The wrapper exits unless
  `CANUTO_OBSIDIAN_PLUGIN_ACTIVE=1`.
- Browser QA and Obsidian disabled manifests retire their corresponding legacy
  global registrations (`CU-32`, `CU-48`, `CX-16`) without removing unrelated
  external hooks.
- Vercel and Codex Companion remain plugin-owned external integrations with
  explicit contracts for ownership, state scope, telemetry, retention, timeout
  and stop-review behavior.
- Vercel and Codex Companion now expose external-owner manifests accepted by
  the `--plan-plugin` / `--verify-plugin` flow plus retirement-only disabled
  manifests. Enabled verification preserves owner-plugin registrations without
  writes; disabled flow removes duplicated host registrations for those
  commands. Canuto does not copy or own the plugin runtime.
- Herdr remains externally owned by the Herdr installer and has an isolated
  profile at `~/.config/herdr/agent-routes/profiles/claude/settings.json`.
  Canuto ships only a retirement manifest for the legacy global registration.
- gstack remains externally owned by the gstack skill. Its installed owner is
  ready via `bin/gstack-settings-hook`, `setup`, `bin/gstack-uninstall` and
  schema-aware prune/remove tests at repo SHA
  `ad8400543cd9ce8d07641362db48d44a95417e33`.

## External Ownership And Retirement Decisions

- gstack `CU-11`, `CU-12`, `CU-35`, `CU-42` are owner-ready in the external
  gstack skill and should be managed there, not copied into Canuto.
- Herdr `CU-50` is retirement-only in Canuto; execution is expected only through
  the isolated Herdr profile.
- Vercel `PV-01`..`PV-04` and Codex Companion `PC-01`..`PC-03` are not copied
  into this repo. The source receipts point at their plugin caches and upstream
  commit SHAs; Canuto only owns retirement of duplicate host registrations.

## Validation Surface

- `node --test .agents/plugins/integration-governance.test.mjs`
- `node --test .agents/plugins/canuto/canuto-hook.test.mjs .agents/plugins/integration-governance.test.mjs`
- `bash test-framework.sh` includes the T8 plugin governance suite.
