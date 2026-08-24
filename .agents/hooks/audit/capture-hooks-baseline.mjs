#!/usr/bin/env node

import { createHash } from "node:crypto";
import { existsSync, readFileSync, statSync, writeFileSync } from "node:fs";
import { basename, join, relative, resolve } from "node:path";
import { fileURLToPath, pathToFileURL } from "node:url";

const ROLES = new Set(["Gate", "Advisory", "Observer", "Automation", "Probe"]);
const EXPECTED_SURFACES = {
  "claude-user": 57,
  "codex-user": 17,
  "plugin-vercel": 4,
  "plugin-codex-companion": 3,
};
const EXPECTED_EVENTS = {
  PreToolUse: 36,
  PostToolUse: 13,
  SessionStart: 11,
  Stop: 8,
  SessionEnd: 5,
  Notification: 2,
  StopFailure: 1,
  SubagentStart: 1,
  SubagentStop: 1,
  TeammateIdle: 1,
  TaskCompleted: 1,
  UserPromptSubmit: 1,
};
const identityManifest = JSON.parse(readFileSync(new URL("hook-identities.json", import.meta.url), "utf8"));
const pluginSourceReceipts = JSON.parse(readFileSync(new URL("plugin-source-receipts.json", import.meta.url), "utf8"));
const identityIdByKey = new Map();
const identityIds = new Set();

function identityKey({ surface, event, matcher, handler }) {
  return stableJson({ surface, event, matcher, handler });
}

for (const identity of identityManifest.records ?? []) {
  const key = identityKey(identity);
  if (identityIdByKey.has(key)) throw new Error(`duplicate hook identity for ${identity.id}`);
  if (identityIds.has(identity.id)) throw new Error(`duplicate hook identity id ${identity.id}`);
  identityIdByKey.set(key, identity.id);
  identityIds.add(identity.id);
}
if (identityManifest.schemaVersion !== 1 || identityIds.size !== 81) {
  throw new Error(`hook identity manifest must cover 81 records, got ${identityIds.size}`);
}
if (pluginSourceReceipts.schemaVersion !== 1) throw new Error("plugin source receipts schemaVersion must be 1");
const pluginReceiptsByDigest = new Map(
  Object.values(pluginSourceReceipts.plugins ?? {}).map((receipt) => [sha256(stableJson(receipt)), receipt]),
);

const metadata = new Map();

function assign(ids, values) {
  for (const id of ids) metadata.set(id, { ...metadata.get(id), ...values });
}

function ids(prefix, numbers) {
  return numbers.map((number) => `${prefix}-${String(number).padStart(2, "0")}`);
}

assign(ids("CU", [1]), { role: "Automation", owner: "repository", disposition: "move" });
assign(ids("CU", [2]), { role: "Advisory", owner: "repository", disposition: "replace" });
assign(ids("CU", [3, 6]), { role: "Observer", owner: "repository", disposition: "replace" });
assign(ids("CU", [5]), { role: "Automation", owner: "repository", disposition: "replace" });
assign(ids("CU", [28]), { role: "Gate", owner: "repository", disposition: "replace" });
assign(ids("CU", [37]), { role: "Advisory", owner: "repository", disposition: "replace" });
assign(ids("CU", [4]), { role: "Automation", owner: "skill:api-reference", disposition: "move" });
assign(ids("CU", [39]), { role: "Advisory", owner: "skill:api-reference", disposition: "move" });
assign(ids("CU", [7]), { role: "Advisory", owner: "none", disposition: "remove" });
assign(ids("CU", [8]), { role: "Observer", owner: "machine-or-plugin:telemetry", disposition: "replace" });
assign(ids("CU", [9]), { role: "Automation", owner: "skill:plan-review", disposition: "move" });
assign(ids("CU", [10]), { role: "Advisory", owner: "orchestrator", disposition: "move" });
assign(ids("CU", [11]), { role: "Observer", owner: "plugin:gstack", disposition: "move" });
assign(ids("CU", [12]), { role: "Advisory", owner: "plugin:gstack", disposition: "move" });
assign(ids("CU", [35, 42]), { role: "Automation", owner: "plugin:gstack", disposition: "move" });
assign(ids("CU", [13, 16, 17, 19, 24]), { role: "Gate", owner: "machine", disposition: "replace" });
assign(ids("CU", [57]), { role: "Advisory", owner: "machine", disposition: "replace" });
assign(ids("CU", [14, 15, 18, 22, 25, 29, 33]), { role: "Gate", owner: "repository", disposition: "replace" });
assign(ids("CU", [20]), { role: "Observer", owner: "none", disposition: "remove" });
assign(ids("CU", [21, 34]), { role: "Automation", owner: "runtime:rtk", disposition: "consolidate" });
assign(ids("CU", [23]), { role: "Gate", owner: "repository:Dobra", disposition: "move" });
assign(ids("CU", [26]), { role: "Gate", owner: "repository-and-skill:review", disposition: "replace" });
assign(ids("CU", [27]), { role: "Gate", owner: "machine-and-repository", disposition: "split" });
assign(ids("CU", [30]), { role: "Advisory", owner: "repository-or-skill:claims", disposition: "replace" });
assign(ids("CU", [31]), { role: "Advisory", owner: "none", disposition: "remove" });
assign(ids("CU", [32]), { role: "Gate", owner: "plugin:qa-browser", disposition: "move" });
assign(ids("CU", [36]), { role: "Advisory", owner: "machine", disposition: "correct" });
assign(ids("CU", [38, 43, 45]), { role: "Automation", owner: "plugin:Canuto", disposition: "move" });
assign(ids("CU", [49]), { role: "Advisory", owner: "plugin:Canuto", disposition: "move" });
assign(ids("CU", [40, 44, 46, 51, 52, 53, 54, 55, 56]), { role: "Observer", owner: "none", disposition: "remove" });
assign(ids("CU", [41]), { role: "Advisory", owner: "repository", disposition: "replace" });
assign(ids("CU", [47]), { role: "Advisory", owner: "machine", disposition: "correct" });
assign(ids("CU", [48]), { role: "Automation", owner: "plugin:Obsidian", disposition: "move" });
assign(ids("CU", [50]), { role: "Observer", owner: "plugin:Herdr", disposition: "move" });

assign(ids("CX", [1, 15]), { role: "Observer", owner: "plugin:Canuto", disposition: "move" });
assign(ids("CX", [2]), { role: "Probe", owner: "none", disposition: "remove" });
assign(ids("CX", [3, 17]), { role: "Automation", owner: "plugin:Canuto", disposition: "move" });
assign(ids("CX", [4]), { role: "Gate", owner: "machine-and-repository", disposition: "split" });
assign(ids("CX", [5, 6, 7, 8]), { role: "Gate", owner: "machine", disposition: "replace" });
assign(ids("CX", [9, 10, 11, 12, 13, 14]), { role: "Gate", owner: "repository", disposition: "replace" });
assign(ids("CX", [16]), { role: "Automation", owner: "plugin:Obsidian", disposition: "move" });

assign(ids("PV", [1, 4]), { role: "Automation", owner: "plugin:Vercel", disposition: "keep" });
assign(ids("PV", [2]), { role: "Observer", owner: "plugin:Vercel", disposition: "keep" });
assign(ids("PV", [3]), { role: "Advisory", owner: "plugin:Vercel", disposition: "keep" });
assign(ids("PC", [1, 2]), { role: "Automation", owner: "plugin:Codex-Companion", disposition: "keep" });
assign(ids("PC", [3]), { role: "Gate", owner: "plugin:Codex-Companion", disposition: "keep" });

function sha256(value) {
  return createHash("sha256").update(value).digest("hex");
}

function stableJson(value) {
  if (Array.isArray(value)) return `[${value.map(stableJson).join(",")}]`;
  if (value && typeof value === "object") {
    return `{${Object.keys(value).sort().map((key) => `${JSON.stringify(key)}:${stableJson(value[key])}`).join(",")}}`;
  }
  return JSON.stringify(value);
}

function readHooks(path) {
  const parsed = JSON.parse(readFileSync(path, "utf8"));
  if (!parsed.hooks || typeof parsed.hooks !== "object" || Array.isArray(parsed.hooks)) {
    throw new Error(`hooks object missing: ${path}`);
  }
  return parsed.hooks;
}

function flattenHooks(hooks) {
  const records = [];
  for (const [event, groups] of Object.entries(hooks)) {
    for (const group of groups) {
      for (const hook of group.hooks ?? []) {
        records.push({
          event,
          matcher: group.matcher ?? "",
          timeout: hook.timeout ?? null,
          command: hook.command,
        });
      }
    }
  }
  return records;
}

function artifactPaths(command, home, pluginRoot) {
  const expanded = command
    .replaceAll("${CLAUDE_PLUGIN_ROOT}", pluginRoot ?? "")
    .replaceAll("$CLAUDE_PLUGIN_ROOT", pluginRoot ?? "")
    .replaceAll("~/", `${home}/`);
  const tokens = expanded.match(/"[^"]+"|'[^']+'|[^\s]+/g) ?? [];
  const paths = [];
  for (const rawToken of tokens) {
    const token = rawToken.replace(/^["']|["';|&(),]+$/g, "");
    if (!token.startsWith("/")) continue;
    if (!existsSync(token) || !statSync(token).isFile()) continue;
    if (!paths.includes(token)) paths.push(token);
  }
  return paths;
}

function handlerLabel(command, artifacts) {
  if (command.includes("ccgram.main")) return "ccgram.main";
  if (command.includes("prettier")) return "inline-prettier";
  if (command.includes("rm -rf")) return "inline-rm-rf-gate";
  if (/\brtk\s+hook\s+claude\b/.test(command)) return "rtk-hook-claude";
  if (artifacts.length > 0) return artifacts.map((path) => basename(path)).join(" -> ");
  const pathLike = command.match(/[A-Za-z0-9_.-]+(?:\.sh|\.mjs|\.js|\.py|[-_]hook)\b/g);
  return pathLike?.at(-1) ?? "inline-command";
}

function repoSource(repoRoot, artifactName) {
  const candidates = [
    join(repoRoot, ".agents", "hooks", artifactName),
    join(repoRoot, ".agents", "hooks", "_retired", artifactName),
  ];
  return candidates.find((candidate) => existsSync(candidate) && statSync(candidate).isFile()) ?? null;
}

function sourceFor(record, repoRoot, sourceCommandDigests, plugin) {
  if (record.disposition === "remove") {
    return { state: "removal-approved", refs: [] };
  }
  if (plugin) {
    const receipt = pluginSourceReceipts.plugins?.[`${plugin.name}@${plugin.version}`];
    const refs = receipt ? [`${receipt.remote}#${receipt.commitSha}:${receipt.sourceRoot}`] : [];
    if (record.artifacts.length === 0 || plugin.pathVersion !== plugin.version || !receipt) {
      return { state: "missing", refs };
    }
    const artifactsMatch = record.artifacts.every((artifact) =>
      artifact.pluginRelativePath
      && receipt.artifacts?.[artifact.pluginRelativePath] === artifact.sha256);
    if (receipt.hookConfig?.sha256 !== plugin.hookConfigSha256 || !artifactsMatch) {
      return { state: "diverged-or-partial", refs };
    }
    if (!/^[a-f0-9]{40}$/.test(receipt.commitSha)) {
      return { state: "missing", refs };
    }
    return {
      state: "versioned-plugin",
      refs,
      hookConfigSha256: plugin.hookConfigSha256,
      commitSha: receipt.commitSha,
      receiptSha256: sha256(stableJson(receipt)),
    };
  }
  const refs = [];
  let compared = 0;
  let exact = 0;
  for (const artifact of record.artifacts) {
    const sourcePath = repoSource(repoRoot, artifact.name);
    if (!sourcePath) continue;
    compared += 1;
    const sourceDigest = sha256(readFileSync(sourcePath));
    refs.push(relative(repoRoot, sourcePath));
    if (sourceDigest === artifact.sha256) exact += 1;
  }
  if (sourceCommandDigests.has(record.commandSha256)) {
    compared += 1;
    exact += 1;
    refs.push(".agents/hooks/settings-snippet.json");
  }
  if (compared === 0) return { state: "missing", refs: [] };
  if (exact !== compared || compared < Math.max(1, record.artifacts.length)) {
    return { state: "diverged-or-partial", refs: [...new Set(refs)].sort() };
  }
  return { state: "exact", refs: [...new Set(refs)].sort() };
}

function normalizeSurface({ hooks, surface, home, pluginRoot, plugin, repoRoot, sourceCommandDigests }) {
  return flattenHooks(hooks).map((hook) => {
    const paths = artifactPaths(hook.command, home, pluginRoot);
    const handler = handlerLabel(hook.command, paths);
    const id = identityIdByKey.get(identityKey({ surface, event: hook.event, matcher: hook.matcher, handler }));
    if (!id) throw new Error(`unknown hook identity: ${surface}/${hook.event}/${hook.matcher}/${handler}`);
    const meta = metadata.get(id);
    if (!meta) throw new Error(`metadata missing for ${id}`);
    const record = {
      id,
      surface,
      event: hook.event,
      matcher: hook.matcher,
      timeoutSeconds: hook.timeout,
      handler,
      commandSha256: sha256(hook.command),
      artifacts: paths.map((path) => ({
        name: basename(path),
        sha256: sha256(readFileSync(path)),
        ...(pluginRoot ? { pluginRelativePath: relative(pluginRoot, path) } : {}),
      })),
      ...meta,
    };
    record.source = sourceFor(record, repoRoot, sourceCommandDigests, plugin);
    record.batchStatus = ["exact", "versioned-plugin", "removal-approved"].includes(record.source.state)
      ? "eligible-for-later-plan"
      : "blocked-source-provenance";
    return record;
  });
}

export function captureBaseline({
  claudeSettings,
  codexHooks,
  plugins,
  repoRoot,
  home,
  capturedAt,
  baseSha,
  branch,
}) {
  const snippetHooks = readHooks(join(repoRoot, ".agents", "hooks", "settings-snippet.json"));
  const sourceCommandDigests = new Set(flattenHooks(snippetHooks).map((hook) => sha256(hook.command)));
  const surfaces = [
    { hooks: readHooks(claudeSettings), surface: "claude-user" },
    { hooks: readHooks(codexHooks), surface: "codex-user" },
    ...plugins.map((plugin) => ({
      hooks: readHooks(plugin.hooksPath),
      surface: plugin.surface,
      pluginRoot: resolve(plugin.hooksPath, "../.."),
      plugin: {
        ...plugin,
        pathVersion: basename(resolve(plugin.hooksPath, "../..")),
        hookConfigSha256: sha256(readFileSync(plugin.hooksPath)),
      },
    })),
  ];
  const records = surfaces.flatMap((surface) => normalizeSurface({
    ...surface,
    home,
    repoRoot,
    sourceCommandDigests,
  }));
  const hooksOnly = {
    "claude-user": readHooks(claudeSettings),
    "codex-user": readHooks(codexHooks),
    ...Object.fromEntries(plugins.map((plugin) => [plugin.surface, readHooks(plugin.hooksPath)])),
  };
  return {
    schemaVersion: 1,
    capturedAt,
    repository: "csorodrigo/canuto-framework",
    baseSha,
    branch,
    privacy: {
      exportedTopLevelFields: ["hooks"],
      rawCommandsExported: false,
      absolutePathsExported: false,
    },
    inputHookDigests: Object.fromEntries(
      Object.entries(hooksOnly).map(([surface, hooks]) => [surface, sha256(stableJson(hooks))]),
    ),
    records,
  };
}

export function validateBaseline(baseline) {
  const errors = [];
  const eligibleSourceStates = new Set(["exact", "versioned-plugin", "removal-approved"]);
  if (baseline.schemaVersion !== 1) errors.push("schemaVersion must be 1");
  if (baseline.records?.length !== 81) errors.push(`expected 81 records, got ${baseline.records?.length ?? 0}`);
  const idsSeen = new Set();
  const surfaceCounts = {};
  const eventCounts = {};
  for (const record of baseline.records ?? []) {
    if (idsSeen.has(record.id)) errors.push(`duplicate id ${record.id}`);
    idsSeen.add(record.id);
    if (identityIdByKey.get(identityKey(record)) !== record.id) errors.push(`identity mismatch for ${record.id}`);
    surfaceCounts[record.surface] = (surfaceCounts[record.surface] ?? 0) + 1;
    eventCounts[record.event] = (eventCounts[record.event] ?? 0) + 1;
    if (!ROLES.has(record.role)) errors.push(`invalid role for ${record.id}`);
    if (!record.owner || !record.disposition) errors.push(`missing responsibility for ${record.id}`);
    if (!record.source?.state) errors.push(`missing source state for ${record.id}`);
    if (record.source?.state === "versioned-plugin" && record.artifacts.length === 0) {
      errors.push(`versioned plugin artifact missing for ${record.id}`);
    }
    if (record.source?.state === "versioned-plugin" && !/^[a-f0-9]{64}$/.test(record.source.receiptSha256 ?? "")) {
      errors.push(`versioned plugin receipt missing for ${record.id}`);
    }
    if (record.source?.state === "versioned-plugin") {
      const receipt = pluginReceiptsByDigest.get(record.source.receiptSha256);
      if (!receipt) {
        errors.push(`unknown plugin source receipt for ${record.id}`);
      } else {
        if (record.source.commitSha !== receipt.commitSha || record.source.hookConfigSha256 !== receipt.hookConfig.sha256) {
          errors.push(`plugin source receipt mismatch for ${record.id}`);
        }
        for (const artifact of record.artifacts ?? []) {
          if (receipt.artifacts?.[artifact.pluginRelativePath] !== artifact.sha256) {
            errors.push(`plugin artifact differs from pinned source for ${record.id}`);
          }
        }
      }
    }
    const expectedBatchStatus = eligibleSourceStates.has(record.source?.state)
      ? "eligible-for-later-plan"
      : "blocked-source-provenance";
    if (record.batchStatus !== expectedBatchStatus) {
      errors.push(`source state ${record.source?.state ?? "absent"} has invalid batch status for ${record.id}`);
    }
    if (!/^[a-f0-9]{64}$/.test(record.commandSha256 ?? "")) errors.push(`invalid command digest for ${record.id}`);
    for (const artifact of record.artifacts ?? []) {
      if (artifact.name.includes("/")) errors.push(`artifact path leaked for ${record.id}`);
      if (artifact.pluginRelativePath?.startsWith("/") || artifact.pluginRelativePath?.includes("..")) {
        errors.push(`unsafe plugin-relative path for ${record.id}`);
      }
      if (!/^[a-f0-9]{64}$/.test(artifact.sha256 ?? "")) errors.push(`invalid artifact digest for ${record.id}`);
    }
  }
  for (const [surface, expected] of Object.entries(EXPECTED_SURFACES)) {
    if (surfaceCounts[surface] !== expected) errors.push(`${surface}: expected ${expected}, got ${surfaceCounts[surface] ?? 0}`);
  }
  for (const [event, expected] of Object.entries(EXPECTED_EVENTS)) {
    if (eventCounts[event] !== expected) errors.push(`${event}: expected ${expected}, got ${eventCounts[event] ?? 0}`);
  }
  for (const expectedId of metadata.keys()) {
    if (!idsSeen.has(expectedId)) errors.push(`missing id ${expectedId}`);
  }
  const serialized = JSON.stringify(baseline);
  if (serialized.includes("/Users/") || serialized.includes("/home/")) errors.push("absolute home path leaked");
  if (/"command"\s*:/.test(serialized)) errors.push("raw command leaked");
  if (metadata.size !== 81) errors.push(`metadata must cover 81 ids, got ${metadata.size}`);
  if (identityIds.size !== 81) errors.push(`identity manifest must cover 81 ids, got ${identityIds.size}`);
  return errors;
}

export function buildProvenanceManifest(baseline, fixtureBytes, fixturePath) {
  return {
    schemaVersion: 1,
    inventoryFixture: fixturePath,
    inventorySha256: sha256(fixtureBytes),
    recordCount: baseline.records.length,
    records: baseline.records.map(({ id, owner, disposition, source, batchStatus }) => ({
      id,
      owner,
      disposition,
      source,
      batchStatus,
    })),
  };
}

export function validateProvenanceManifest(manifest, baseline, fixtureBytes) {
  const errors = [];
  if (manifest.schemaVersion !== 1) errors.push("provenance schemaVersion must be 1");
  if (manifest.recordCount !== 81 || manifest.records?.length !== 81) errors.push("provenance must cover 81 records");
  if (manifest.inventorySha256 !== sha256(fixtureBytes)) errors.push("provenance fixture digest mismatch");
  const baselineById = new Map(baseline.records.map((record) => [record.id, record]));
  const manifestIds = new Set();
  for (const record of manifest.records ?? []) {
    if (manifestIds.has(record.id)) errors.push(`duplicate provenance id ${record.id}`);
    manifestIds.add(record.id);
    const expected = baselineById.get(record.id);
    if (!expected) {
      errors.push(`provenance has unknown id ${record.id}`);
      continue;
    }
    for (const field of ["owner", "disposition", "batchStatus"]) {
      if (record[field] !== expected[field]) errors.push(`provenance ${field} mismatch for ${record.id}`);
    }
    if (stableJson(record.source) !== stableJson(expected.source)) errors.push(`provenance source mismatch for ${record.id}`);
  }
  for (const id of baselineById.keys()) {
    if (!manifestIds.has(id)) errors.push(`provenance missing id ${id}`);
  }
  return errors;
}

function parseArgs(argv) {
  const values = {};
  for (let index = 0; index < argv.length; index += 2) {
    const key = argv[index];
    const value = argv[index + 1];
    if (!key?.startsWith("--") || value === undefined) throw new Error(`invalid argument near ${key ?? "end"}`);
    values[key.slice(2)] = value;
  }
  return values;
}

function main(argv) {
  const [action, ...rest] = argv;
  if (action === "validate") {
    const [path] = rest;
    const errors = validateBaseline(JSON.parse(readFileSync(path, "utf8")));
    if (errors.length > 0) throw new Error(errors.join("\n"));
    process.stdout.write("hooks baseline: PASS (81/81)\n");
    return;
  }
  if (action === "provenance") {
    const args = parseArgs(rest);
    const fixtureBytes = readFileSync(args.fixture);
    const baseline = JSON.parse(fixtureBytes);
    const baselineErrors = validateBaseline(baseline);
    if (baselineErrors.length > 0) throw new Error(baselineErrors.join("\n"));
    const manifest = buildProvenanceManifest(baseline, fixtureBytes, args.fixture);
    writeFileSync(args.output, `${JSON.stringify(manifest, null, 2)}\n`, { flag: "wx" });
    return;
  }
  if (action === "validate-provenance") {
    const [manifestPath, fixturePath] = rest;
    const fixtureBytes = readFileSync(fixturePath);
    const baseline = JSON.parse(fixtureBytes);
    const manifest = JSON.parse(readFileSync(manifestPath, "utf8"));
    const errors = [
      ...validateBaseline(baseline),
      ...validateProvenanceManifest(manifest, baseline, fixtureBytes),
    ];
    if (errors.length > 0) throw new Error(errors.join("\n"));
    process.stdout.write("hooks provenance: PASS (81/81)\n");
    return;
  }
  if (action !== "capture") throw new Error("usage: capture-hooks-baseline.mjs <capture|validate> ...");
  const args = parseArgs(rest);
  const repoRoot = resolve(fileURLToPath(new URL("../../..", import.meta.url)));
  const baseline = captureBaseline({
    claudeSettings: args["claude-settings"],
    codexHooks: args["codex-hooks"],
    repoRoot,
    home: args.home,
    capturedAt: args["captured-at"],
    baseSha: args["base-sha"],
    branch: args.branch,
    plugins: [
      { name: "vercel", version: args["vercel-version"], hooksPath: args["vercel-hooks"], surface: "plugin-vercel", prefix: "PV" },
      { name: "codex-companion", version: args["companion-version"], hooksPath: args["companion-hooks"], surface: "plugin-codex-companion", prefix: "PC" },
    ],
  });
  const errors = validateBaseline(baseline);
  if (errors.length > 0) throw new Error(errors.join("\n"));
  writeFileSync(args.output, `${JSON.stringify(baseline, null, 2)}\n`, { flag: "wx" });
}

if (import.meta.url === pathToFileURL(process.argv[1]).href) {
  try {
    main(process.argv.slice(2));
  } catch (error) {
    process.stderr.write(`${error.message}\n`);
    process.exitCode = 1;
  }
}
