import { normalizeClaudeInvocation, renderClaudePolicyResponse } from "../adapters/claude/index.mjs";
import { normalizeCodexInvocation, renderCodexPolicyResponse } from "../adapters/codex/index.mjs";
import { allow, block, composePolicyResults } from "../core/policy-result.mjs";
import { captureExecutionIdentity, discoverExecutionRoot } from "../core/execution-identity.mjs";
import { resolveRepoPolicy } from "../repo-policy-loader.mjs";
import { runMachinePolicies } from "./machine-policy-runner.mjs";

const COMMAND_MATCHERS = Object.freeze([
  ["branch-creation", /(?:^|[;&|\s])git(?:\s+-\S+(?:=\S+|\s+\S+))*\s+(?:(?:checkout\s+(?:-[A-Za-z]*b|--branch)(?:=|\s+)\S+)|(?:switch\s+(?:-[A-Za-z]*c|--create)(?:=|\s+)\S+)|(?:branch\s+(?!--(?:list|show-current|contains|merged|no-merged|delete|move|copy)\b)(?!-[dDmMcC]\b)[^-\s][^\s]*))(?:\s|$)/],
  ["build-typecheck", /(?:^|[;&|\s])(?:(?:npm|pnpm|yarn|bun)\s+(?:run\s+)?(?:build|typecheck(?::codex)?)|(?:npx\s+)?tsc(?:\s|$))/],
  ["deploy-target", /(?:^|[;&|\s])(?:(?:npm|pnpm|yarn|bun)\s+(?:run\s+)?deploy|vercel\s+(?:deploy|--prod)|railway\s+up|dokploy\s+deploy)(?:\s|$)/],
  ["validation-receipt", /(?:validation-(?:mark|clear)\.sh|canuto-validation\s+(?:mark|verify)|verify-execution-receipt)/],
  ["commit", /(?:^|[;&|\s])git(?:\s+-\S+(?:=\S+|\s+\S+))*\s+commit(?:\s|$)/],
  ["pull-request", /(?:^|[;&|\s])(?:gh(?:\s+-(?:R|C)\s+\S+|\s+--(?:repo|hostname)(?:=\S+|\s+\S+))*\s+pr\s+(?:create|merge)|(?:\S*\/)?pr-merge\.sh)(?:\s|$)/],
  ["claims", /(?:pre-claim-grep|claim-guard|canuto-claim)(?:\.sh)?(?:\s|$)/],
  ["worktree-dependencies", /(?:worktree-(?:deps|collision)-check)(?:\.sh)?(?:\s|$)/],
]);

export const REPO_POLICY_RUNNER_EFFECTS = Object.freeze({
  reads: Object.freeze(["stdin-hook-payload", ".agents/hooks/manifest.json", "git-execution-identity", "machine-policy-evidence"]),
  writes: Object.freeze(["stdout-native-response"]),
  network: false,
  persistence: false,
});

function normalize(platform, payload) {
  if (platform === "claude") return normalizeClaudeInvocation(payload);
  if (platform === "codex") return normalizeCodexInvocation(payload);
  throw new Error(`unsupported platform ${platform}`);
}

function render(platform, event, composition) {
  if (platform === "claude") return renderClaudePolicyResponse(event, composition);
  if (platform === "codex") return renderCodexPolicyResponse(event, composition);
  throw new Error(`unsupported platform ${platform}`);
}

function mergeCompositions(machine, repository) {
  const blockers = [...new Set([...machine.blockerIds, ...repository.blockerIds])];
  const reasons = [machine.reason, repository.reason].filter(Boolean);
  return Object.freeze({
    verdict: blockers.length > 0 ? "block" : "allow",
    reason: reasons.join("; "),
    gateIds: Object.freeze([...new Set([...machine.gateIds, ...repository.gateIds])]),
    blockerIds: Object.freeze(blockers),
    advisories: Object.freeze([...machine.advisories, ...repository.advisories]),
  });
}

function toolPolicy(payload) {
  const toolName = typeof payload?.tool_name === "string" ? payload.tool_name : "";
  if (/(?:^|__)claim(?:_|$)|claim[-_]guard/i.test(toolName)) return "claims";
  if (/worktree[-_](?:deps|dependencies|collision)/i.test(toolName)) return "worktree-dependencies";
  return null;
}

export function detectGovernedRepoPolicy(invocation, payload) {
  const matchedToolPolicy = toolPolicy(payload);
  if (matchedToolPolicy) return matchedToolPolicy;
  if (invocation.subjectKind !== "command") return null;
  for (const [policyId, matcher] of COMMAND_MATCHERS) {
    if (matcher.test(invocation.subject)) return policyId;
  }
  return null;
}

function repositoryBlock(policyId, reason) {
  return composePolicyResults([block(`repo:${policyId}`, reason)]);
}

function finish(machineResult, invocation, platform, policyId, repositoryDecision, repositoryComposition) {
  const composition = mergeCompositions(machineResult.composition, repositoryComposition);
  return Object.freeze({
    composition,
    response: render(platform, invocation.event, composition),
    telemetry: Object.freeze({
      ...machineResult.telemetry,
      verdict: composition.verdict,
      gateIds: composition.gateIds,
      blockerIds: composition.blockerIds,
      advisoryIds: Object.freeze(composition.advisories.map((item) => item.id)),
      repositoryPolicyId: policyId,
    }),
    matchedPolicyId: policyId,
    repositoryDecision,
  });
}

function normalizeEvaluatorDecision(policyId, decision) {
  try {
    const composition = composePolicyResults([decision]);
    if (!composition.gateIds.includes(policyId) && !composition.advisories.some((item) => item.id === policyId)) {
      return repositoryBlock(policyId, `repository policy ${policyId} evaluator returned the wrong policy id`);
    }
    return composition;
  } catch {
    return repositoryBlock(policyId, `repository policy ${policyId} evaluator returned an invalid decision`);
  }
}

export async function runRepoPolicies({
  platform,
  payload,
  evaluators = {},
  machineRunner = runMachinePolicies,
  rootResolver = discoverExecutionRoot,
  identityReader = captureExecutionIdentity,
  manifestResolver = resolveRepoPolicy,
  machineOptions = {},
}) {
  const invocation = normalize(platform, payload);
  const machineResult = await machineRunner({ ...machineOptions, platform, payload });
  const policyId = detectGovernedRepoPolicy(invocation, payload);
  if (!policyId || machineResult.composition.verdict === "block") {
    return Object.freeze({ ...machineResult, matchedPolicyId: policyId, repositoryDecision: "no-op" });
  }

  let repoRoot;
  try {
    repoRoot = await rootResolver({ cwd: invocation.cwd });
  } catch {
    return finish(
      machineResult,
      invocation,
      platform,
      policyId,
      "block",
      repositoryBlock(policyId, "repository Git identity could not be resolved"),
    );
  }
  if (!repoRoot) {
    return Object.freeze({ ...machineResult, matchedPolicyId: policyId, repositoryDecision: "no-op" });
  }

  let resolution;
  try {
    resolution = await manifestResolver({ repoRoot, policyId });
  } catch {
    resolution = { decision: "block", manifestStatus: "invalid", errors: ["repository policy manifest could not be resolved"] };
  }
  if (resolution.decision === "no-op") {
    return Object.freeze({ ...machineResult, matchedPolicyId: policyId, repositoryDecision: "no-op" });
  }

  let repositoryComposition;
  if (resolution.decision === "block") {
    repositoryComposition = repositoryBlock(policyId, resolution.errors?.join("; ") || "repository policy manifest is invalid");
  } else {
    const evaluator = evaluators[policyId];
    if (typeof evaluator !== "function") {
      repositoryComposition = repositoryBlock(policyId, `repository policy ${policyId} has no evaluator`);
    } else {
      try {
        const identity = await identityReader({ cwd: invocation.cwd, sessionId: invocation.sessionId });
        const decision = await evaluator({ invocation, payload, policy: resolution.policy, identity });
        repositoryComposition = normalizeEvaluatorDecision(policyId, decision);
      } catch {
        repositoryComposition = repositoryBlock(policyId, `repository policy ${policyId} evaluator or identity evidence is unavailable`);
      }
    }
  }

  return finish(machineResult, invocation, platform, policyId, resolution.decision, repositoryComposition);
}

export function allowRepoPolicy(policyId, reason = "repository policy satisfied") {
  return allow(policyId, reason);
}
