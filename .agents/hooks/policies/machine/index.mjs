import { block, composePolicyResults } from "../../core/policy-result.mjs";
import { evaluateBroadDestruction } from "./broad-destruction.mjs";
import { evaluateHostPressure } from "./host-pressure.mjs";
import { evaluateProcessSelfMatch } from "./process-self-match.mjs";
import { evaluateProtectedRead } from "./protected-read.mjs";
import { evaluateSecretMaterial } from "./secret-material.mjs";

const EVALUATION_ERROR_ID = "machine.policy-evaluation";

function failClosed(evaluator) {
  try {
    const value = evaluator();
    return Array.isArray(value) ? value : [value];
  } catch {
    return [block(EVALUATION_ERROR_ID, "machine policy evaluation failed")];
  }
}

export function evaluateMachinePolicies(invocation, { hostEvidence = null, trustedOverrides = new Set() } = {}) {
  if (!(trustedOverrides instanceof Set)) throw new Error("trusted overrides must be a Set");
  const decisions = [
    ...failClosed(() => evaluateSecretMaterial(invocation)),
    ...failClosed(() => evaluateProtectedRead(invocation)),
    ...failClosed(() => evaluateProcessSelfMatch(invocation, { trustedOverrides })),
    ...failClosed(() => evaluateBroadDestruction(invocation, { trustedOverrides })),
    ...failClosed(() => evaluateHostPressure(invocation, hostEvidence, { trustedOverrides })),
  ];
  return composePolicyResults(decisions);
}
