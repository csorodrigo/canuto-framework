import assert from "node:assert/strict";
import { mkdtempSync, mkdirSync, readFileSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import test from "node:test";

import {
  buildProvenanceManifest,
  captureBaseline,
  validateBaseline,
  validateProvenanceManifest,
} from "./capture-hooks-baseline.mjs";

function writeJson(path, value) {
  writeFileSync(path, JSON.stringify(value));
}

test("validator rejects incomplete inventory", () => {
  const errors = validateBaseline({ schemaVersion: 1, records: [] });
  assert.ok(errors.some((error) => error.includes("expected 81 records")));
});

test("validator fails closed for a divergent source", () => {
  const fixture = JSON.parse(readFileSync(new URL("fixtures/active-hooks-2026-08-24.json", import.meta.url), "utf8"));
  const divergent = fixture.records.find((record) => record.source.state === "diverged-or-partial");
  divergent.batchStatus = "eligible-for-later-plan";
  const errors = validateBaseline(fixture);
  assert.ok(errors.some((error) => error.includes(`invalid batch status for ${divergent.id}`)));
});

test("validator binds each stable id to its semantic identity", () => {
  const fixture = JSON.parse(readFileSync(new URL("fixtures/active-hooks-2026-08-24.json", import.meta.url), "utf8"));
  fixture.records.find((record) => record.id === "CU-01").handler = "another-handler";
  assert.ok(validateBaseline(fixture).includes("identity mismatch for CU-01"));
});

test("plugin provenance is compared with pinned source receipts", () => {
  const fixture = JSON.parse(readFileSync(new URL("fixtures/active-hooks-2026-08-24.json", import.meta.url), "utf8"));
  const exactPlugin = fixture.records.find((record) => record.id === "PV-01");
  const divergentPlugin = fixture.records.find((record) => record.id === "PV-02");
  assert.equal(exactPlugin.source.state, "versioned-plugin");
  assert.match(exactPlugin.source.commitSha, /^[a-f0-9]{40}$/);
  assert.match(exactPlugin.source.receiptSha256, /^[a-f0-9]{64}$/);
  assert.equal(divergentPlugin.source.state, "diverged-or-partial");
  assert.equal(divergentPlugin.batchStatus, "blocked-source-provenance");
  exactPlugin.artifacts[0].sha256 = "0".repeat(64);
  assert.ok(validateBaseline(fixture).some((error) => error.includes("differs from pinned source for PV-01")));
});

test("capture exports hooks only and never raw commands or absolute paths", () => {
  const root = mkdtempSync(join(tmpdir(), "canuto-hooks-audit-"));
  const repoRoot = join(root, "repo");
  const hooksRoot = join(repoRoot, ".agents", "hooks");
  mkdirSync(hooksRoot, { recursive: true });
  writeJson(join(hooksRoot, "settings-snippet.json"), {
    hooks: { PostToolUse: [] },
  });
  const claudePath = join(root, "claude.json");
  const codexPath = join(root, "codex.json");
  const vercelRoot = join(root, "vercel", "fixture");
  const companionRoot = join(root, "companion", "fixture");
  const vercelHooksPath = join(vercelRoot, "hooks", "hooks.json");
  const companionHooksPath = join(companionRoot, "hooks", "hooks.json");
  mkdirSync(join(vercelRoot, "hooks"), { recursive: true });
  mkdirSync(join(companionRoot, "hooks"), { recursive: true });
  mkdirSync(join(companionRoot, "scripts"), { recursive: true });
  const typecheckPath = join(root, "posttool-typecheck.sh");
  writeFileSync(typecheckPath, "#!/usr/bin/env bash\n");
  writeFileSync(join(vercelRoot, "hooks", "session-start-seen-skills.mjs"), "export {};\n");
  writeFileSync(join(companionRoot, "scripts", "session-lifecycle-hook.mjs"), "export {};\n");
  writeJson(claudePath, {
    hooks: {
      PostToolUse: [{
        matcher: "Edit|Write",
        hooks: [
          { command: typecheckPath },
          { command: "command -v prettier >/dev/null && prettier --write" },
        ],
      }],
    },
    sensitiveFixture: "must-not-leak",
  });
  writeJson(codexPath, { hooks: { PreToolUse: [] }, anotherSensitiveFixture: "must-not-leak" });
  writeJson(vercelHooksPath, {
    hooks: {
      SessionStart: [{
        matcher: "startup|resume|clear|compact",
        hooks: [{ command: 'node "${CLAUDE_PLUGIN_ROOT}/hooks/session-start-seen-skills.mjs"' }],
      }],
    },
  });
  writeJson(companionHooksPath, {
    hooks: { SessionStart: [{ hooks: [{ command: 'node "${CLAUDE_PLUGIN_ROOT}/scripts/session-lifecycle-hook.mjs" SessionStart' }] }] },
  });

  const baseline = captureBaseline({
    claudeSettings: claudePath,
    codexHooks: codexPath,
    plugins: [
      { name: "vercel", version: "fixture", hooksPath: vercelHooksPath, surface: "plugin-vercel" },
      { name: "codex-companion", version: "fixture", hooksPath: companionHooksPath, surface: "plugin-codex-companion" },
    ],
    repoRoot,
    home: root,
    capturedAt: "2026-08-24T00:00:00Z",
    baseSha: "0".repeat(40),
    branch: "fixture",
  });

  const serialized = JSON.stringify(baseline);
  assert.ok(!serialized.includes("must-not-leak"));
  assert.ok(!serialized.includes(root));
  assert.ok(!serialized.includes('"command":'));
  assert.equal(baseline.privacy.exportedTopLevelFields.join(","), "hooks");
  assert.deepEqual(baseline.records.slice(0, 2).map((record) => record.id), ["CU-02", "CU-01"]);
  assert.equal(baseline.records.find((record) => record.id === "PV-01").artifacts.length, 1);
  assert.equal(baseline.records.find((record) => record.id === "PC-01").artifacts.length, 1);
});

test("provenance validator binds the manifest to the exact fixture bytes", () => {
  const baseline = { records: [] };
  const fixtureBytes = Buffer.from('{"records":[]}\n');
  const manifest = buildProvenanceManifest(baseline, fixtureBytes, "fixture.json");
  manifest.inventorySha256 = "0".repeat(64);
  const errors = validateProvenanceManifest(manifest, baseline, fixtureBytes);
  assert.ok(errors.includes("provenance fixture digest mismatch"));
});

test("provenance validator rejects duplicate ids and reports the omitted id", () => {
  const baseline = {
    records: [
      { id: "CU-01", owner: "repository", disposition: "move", source: { state: "missing" }, batchStatus: "blocked-source-provenance" },
      { id: "CU-02", owner: "repository", disposition: "replace", source: { state: "missing" }, batchStatus: "blocked-source-provenance" },
    ],
  };
  const fixtureBytes = Buffer.from(JSON.stringify(baseline));
  const manifest = buildProvenanceManifest(baseline, fixtureBytes, "fixture.json");
  manifest.recordCount = 81;
  manifest.records = [manifest.records[0], manifest.records[0], ...Array(79).fill(manifest.records[0])];
  const errors = validateProvenanceManifest(manifest, baseline, fixtureBytes);
  assert.ok(errors.includes("duplicate provenance id CU-01"));
  assert.ok(errors.includes("provenance missing id CU-02"));
});
