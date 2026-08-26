import { allow, block } from "../../core/policy-result.mjs";

export const BROAD_DESTRUCTION_POLICY_ID = "machine.broad-destruction";

const RM_COMMAND = /(?:^|[;&|]\s*|\b)(?:sudo\s+)?rm\s+([^;&|\n]+)/i;
const BROAD_TARGETS = new Set([
  "/", "/*", "~", "~/", "~/*", "$HOME", "$HOME/*", "${HOME}", "${HOME}/*",
  ".", "..", "./*", "../*", "*", "/Users", "/Users/*", "/home", "/home/*",
  "/var", "/var/*", "/etc", "/etc/*", "/usr", "/usr/*",
]);

function hasRecursiveForce(options) {
  const tokens = options.trim().split(/\s+/);
  const flags = tokens.filter((token) => /^-[A-Za-z]+$/.test(token)).join("");
  const recursive = flags.includes("r") || flags.includes("R") || tokens.includes("--recursive");
  const force = flags.includes("f") || tokens.includes("--force");
  return recursive && force;
}

function hasBroadTarget(options) {
  return options
    .trim()
    .split(/\s+/)
    .filter((token) => token !== "--" && !token.startsWith("-"))
    .map((token) => token.replace(/["']/g, ""))
    .some((token) => BROAD_TARGETS.has(token));
}

export function evaluateBroadDestruction(invocation, { trustedOverrides = new Set() } = {}) {
  if (invocation.subjectKind !== "command") return allow(BROAD_DESTRUCTION_POLICY_ID);
  if (trustedOverrides.has(BROAD_DESTRUCTION_POLICY_ID)) return allow(BROAD_DESTRUCTION_POLICY_ID, "trusted override supplied out of band");
  const match = invocation.subject.match(RM_COMMAND);
  if (!match || !hasRecursiveForce(match[1])) return allow(BROAD_DESTRUCTION_POLICY_ID);
  return hasBroadTarget(match[1])
    ? block(BROAD_DESTRUCTION_POLICY_ID, "broad recursive deletion is not allowed")
    : allow(BROAD_DESTRUCTION_POLICY_ID);
}
