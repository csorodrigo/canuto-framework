import { allow, block } from "../../core/policy-result.mjs";
import { resolveRepoPolicy } from "../../repo-policy-loader.mjs";
import { evaluateBuildTypecheck } from "./build-typecheck.mjs";
import { evaluateDeployTarget } from "./deploy-target.mjs";
import {
  evaluateReceiptConsumer,
  evaluateValidationReceipt,
  readValidationReceipt,
} from "./validation-receipt.mjs";

function allowDeclared(policyId) {
  return () => allow(policyId, `${policyId} is owned by the repository manifest`);
}

export function createRepoPolicyEvaluators({
  receiptReader = readValidationReceipt,
  policyResolver = resolveRepoPolicy,
} = {}) {
  async function receiptConsumer(policyId, context) {
    const receipt = await receiptReader({ identity: context.identity });
    const validationPolicy = await policyResolver({
      repoRoot: context.identity.worktreeRoot,
      policyId: "validation-receipt",
    });
    const allowedArgv = validationPolicy.decision === "apply"
      ? validationPolicy.policy.options?.allowedArgv
      : [];
    return evaluateReceiptConsumer(policyId, { ...context, receipt, allowedArgv });
  }
  return Object.freeze({
    "worktree-dependencies": allowDeclared("worktree-dependencies"),
    "build-typecheck": evaluateBuildTypecheck,
    claims: allowDeclared("claims"),
    "branch-creation": allowDeclared("branch-creation"),
    "deploy-target": evaluateDeployTarget,
    "validation-receipt": evaluateValidationReceipt,
    commit: (context) => receiptConsumer("commit", context),
    "pull-request": (context) => receiptConsumer("pull-request", context),
  });
}

export function unavailableRepositoryPolicy(policyId, reason) {
  return block(policyId, reason);
}
