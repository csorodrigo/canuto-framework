import { allow, block } from "../../core/policy-result.mjs";

function normalizedCommand(command) {
  return command.trim().replace(/^rtk\s+(?:proxy\s+)?/, "");
}

export function evaluateDeployTarget({ invocation, policy }) {
  const targets = policy.options?.targets;
  if (!Array.isArray(targets) || targets.length === 0) {
    return block("deploy-target", "deploy target policy has no project-owned targets");
  }
  const command = normalizedCommand(invocation.subject);
  const target = targets.find((candidate) => candidate
    && typeof candidate === "object"
    && typeof candidate.name === "string"
    && Array.isArray(candidate.commands)
    && candidate.commands.some((item) => typeof item === "string" && normalizedCommand(item) === command));
  return target
    ? allow("deploy-target", `deploy target ${target.name} is declared by the repository`)
    : block("deploy-target", "deploy command has no exact repository-owned target declaration");
}
