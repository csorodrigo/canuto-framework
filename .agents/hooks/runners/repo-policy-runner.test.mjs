import assert from "node:assert/strict";
import { execFile as execFileCallback } from "node:child_process";
import { mkdtemp, mkdir, realpath, rm, writeFile } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { promisify } from "node:util";
import test from "node:test";

import { BROAD_DESTRUCTION_POLICY_ID } from "../policies/machine/broad-destruction.mjs";
import { allowRepoPolicy, runRepoPolicies } from "./repo-policy-runner.mjs";

const execFile = promisify(execFileCallback);

async function git(cwd, ...args) {
  await execFile("git", ["-C", cwd, ...args], { encoding: "utf8" });
}

async function repositoryFixture() {
  const root = await mkdtemp(join(tmpdir(), "canuto-repo-runner-"));
  await git(root, "init", "-b", "main");
  await git(root, "config", "user.name", "Canuto Fixture");
  await git(root, "config", "user.email", "canuto@example.invalid");
  await writeFile(join(root, "tracked.txt"), "initial\n");
  await git(root, "add", "tracked.txt");
  await git(root, "commit", "-m", "fixture");
  return root;
}

async function writeManifest(root, policies, schemaVersion = 1) {
  const hooks = join(root, ".agents", "hooks");
  await mkdir(hooks, { recursive: true });
  await writeFile(join(hooks, "manifest.json"), `${JSON.stringify({
    $schema: "./repo-policy.schema.json",
    schemaVersion,
    policies: policies.map((id) => ({ id })),
  })}\n`);
}

function payload(platform, cwd, command, toolName = "Bash") {
  const common = {
    session_id: `session-${platform}`,
    cwd,
    hook_event_name: "PreToolUse",
    tool_name: toolName,
    tool_input: toolName === "Bash" ? { command } : {},
  };
  return platform === "claude"
    ? common
    : { ...common, turn_id: "turn-codex", model: "fixture-model" };
}

function nativeVerdict(platform, response) {
  if (platform === "codex" && Object.keys(response).length === 0) return "allow";
  return response.hookSpecificOutput.permissionDecision;
}

test("declared commit policy evaluates and renders native allow on Claude and Codex", async (t) => {
  const root = await repositoryFixture();
  t.after(() => rm(root, { recursive: true, force: true }));
  await writeManifest(root, ["commit"]);
  const canonicalRoot = await realpath(root);
  for (const platform of ["claude", "codex"]) {
    let evaluations = 0;
    const result = await runRepoPolicies({
      platform,
      payload: payload(platform, root, "git commit -m fixture"),
      evaluators: {
        commit: ({ identity }) => {
          evaluations += 1;
          assert.equal(identity.worktreeRoot, canonicalRoot);
          return allowRepoPolicy("commit");
        },
      },
    });
    assert.equal(evaluations, 1);
    assert.equal(result.matchedPolicyId, "commit");
    assert.equal(result.repositoryDecision, "apply");
    assert.equal(result.composition.verdict, "allow", result.composition.reason);
    assert.equal(nativeVerdict(platform, result.response), "allow");
  }
});

test("missing, undeclared, invalid, and evaluator-less policies keep fail-safe semantics", async (t) => {
  const root = await repositoryFixture();
  t.after(() => rm(root, { recursive: true, force: true }));
  const command = "git commit -m fixture";
  const missing = await runRepoPolicies({ platform: "codex", payload: payload("codex", root, command) });
  assert.equal(missing.repositoryDecision, "no-op");
  assert.equal(missing.composition.verdict, "allow");

  await writeManifest(root, ["pull-request"]);
  const undeclared = await runRepoPolicies({ platform: "codex", payload: payload("codex", root, command) });
  assert.equal(undeclared.repositoryDecision, "no-op");
  assert.equal(undeclared.composition.verdict, "allow");

  await writeManifest(root, ["commit"], 2);
  for (const platform of ["claude", "codex"]) {
    const invalid = await runRepoPolicies({ platform, payload: payload(platform, root, command) });
    assert.equal(invalid.repositoryDecision, "block");
    assert.equal(invalid.composition.verdict, "block");
    assert.equal(nativeVerdict(platform, invalid.response), "deny");
  }

  await writeManifest(root, ["commit"]);
  const noEvaluator = await runRepoPolicies({ platform: "codex", payload: payload("codex", root, command) });
  assert.equal(noEvaluator.composition.verdict, "block");
  assert.match(noEvaluator.composition.reason, /has no evaluator/);

  const identityUnavailable = await runRepoPolicies({
    platform: "codex",
    payload: payload("codex", root, command),
    rootResolver: async () => { throw new Error("git unavailable"); },
  });
  assert.equal(identityUnavailable.repositoryDecision, "block");
  assert.equal(identityUnavailable.composition.verdict, "block");
  assert.match(identityUnavailable.composition.reason, /Git identity could not be resolved/);
});

test("repository allow never overwrites a machine Gate block", async (t) => {
  const root = await repositoryFixture();
  t.after(() => rm(root, { recursive: true, force: true }));
  await writeManifest(root, ["commit"]);
  for (const platform of ["claude", "codex"]) {
    let evaluations = 0;
    const result = await runRepoPolicies({
      platform,
      payload: payload(platform, root, "rm -rf / && git commit -m unsafe"),
      evaluators: { commit: () => { evaluations += 1; return allowRepoPolicy("commit"); } },
    });
    assert.equal(evaluations, 0);
    assert.equal(result.composition.verdict, "block");
    assert.ok(result.composition.blockerIds.includes(BROAD_DESTRUCTION_POLICY_ID));
    assert.equal(nativeVerdict(platform, result.response), "deny");
  }
});

test("runner detects every initial policy, including claim and worktree tool paths", async (t) => {
  const root = await repositoryFixture();
  t.after(() => rm(root, { recursive: true, force: true }));
  const cases = [
    ["branch-creation", "git switch -c feature", "Bash"],
    ["build-typecheck", "npm run typecheck:codex", "Bash"],
    ["deploy-target", "vercel --prod", "Bash"],
    ["validation-receipt", ".agents/hooks/validation-clear.sh", "Bash"],
    ["validation-receipt", "node .agents/hooks/policies/repo/validation-receipt-cli.mjs verify --session fixture", "Bash"],
    ["commit", "git commit -m fixture", "Bash"],
    ["pull-request", "gh pr create --fill", "Bash"],
    ["claims", "", "mcp__canuto__claim_task"],
    ["worktree-dependencies", "", "mcp__canuto__worktree_dependencies"],
  ];
  for (const [expected, command, toolName] of cases) {
    const result = await runRepoPolicies({
      platform: "codex",
      payload: payload("codex", root, command, toolName),
    });
    assert.equal(result.matchedPolicyId, expected);
    assert.equal(result.repositoryDecision, "no-op");
  }
});

test("common branch and pull-request command forms cannot bypass declared policies", async (t) => {
  const root = await repositoryFixture();
  t.after(() => rm(root, { recursive: true, force: true }));
  await writeManifest(root, ["branch-creation", "pull-request"]);
  const commands = [
    ["branch-creation", "git branch feature"],
    ["branch-creation", "git switch --create=feature"],
    ["pull-request", "gh -R owner/repo pr create --fill"],
  ];
  for (const [expected, command] of commands) {
    const result = await runRepoPolicies({
      platform: "codex",
      payload: payload("codex", root, command),
    });
    assert.equal(result.matchedPolicyId, expected);
    assert.equal(result.repositoryDecision, "apply");
    assert.equal(result.composition.verdict, "block");
    assert.match(result.composition.reason, /has no evaluator/);
  }
});
