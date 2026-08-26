import { allow, block } from "../../core/policy-result.mjs";

function normalizedCommand(command) {
  return command.trim().replace(/^rtk\s+(?:proxy\s+)?/, "");
}

export function evaluateBuildTypecheck({ invocation, policy }) {
  const commands = policy.options?.commands;
  if (!Array.isArray(commands) || commands.length === 0 || commands.some((item) => typeof item !== "string" || !item.trim())) {
    return block("build-typecheck", "build/typecheck policy requires explicit project-owned commands");
  }
  const command = normalizedCommand(invocation.subject);
  const allowed = commands.map(normalizedCommand);
  return allowed.includes(command)
    ? allow("build-typecheck", "project-owned build/typecheck command is declared")
    : block("build-typecheck", `build/typecheck command is not declared by ${policy.id}`);
}
