import { allow, block } from "../../core/policy-result.mjs";

export const PROCESS_SELF_MATCH_POLICY_ID = "machine.process-self-match";

const PS_PIPE_GREP = /\bps\b[^\n|;]*\|[^\n;]*(?:grep|rg)\b/i;
const FULL_COMMAND_PROBE = /\b(?:pgrep|pkill)\b[^\n;]*(?:\s-f\b|--full\b)/i;

export function evaluateProcessSelfMatch(invocation, { trustedOverrides = new Set() } = {}) {
  if (invocation.subjectKind !== "command") return allow(PROCESS_SELF_MATCH_POLICY_ID);
  if (trustedOverrides.has(PROCESS_SELF_MATCH_POLICY_ID)) return allow(PROCESS_SELF_MATCH_POLICY_ID, "trusted override supplied out of band");
  return PS_PIPE_GREP.test(invocation.subject) || FULL_COMMAND_PROBE.test(invocation.subject)
    ? block(PROCESS_SELF_MATCH_POLICY_ID, "process probe can match its own command; use a PID-safe query")
    : allow(PROCESS_SELF_MATCH_POLICY_ID);
}
