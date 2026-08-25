import { advisory, allow, block } from "../../core/policy-result.mjs";

export const SECRET_COMMAND_POLICY_ID = "machine.secret-command";
export const SECRET_PROMPT_POLICY_ID = "machine.secret-prompt";

const CREDENTIAL_PREFIX = /(?:\bAKIA[0-9A-Z]{16}\b|\bghp_[A-Za-z0-9]{20,}\b|\bgithub_pat_[A-Za-z0-9_]{20,}\b|\bxox[baprs]-[A-Za-z0-9-]{10,}\b|\bsk-[A-Za-z0-9_-]{20,}\b)/;
const SENSITIVE_ASSIGNMENT = /(?:api[_-]?key|access[_-]?token|auth[_-]?token|client[_-]?secret|password|private[_-]?key)\s*(?:=|:)\s*["']?(?!\$\{|\$[A-Za-z_]|<|\{\{|example|placeholder|redacted|dummy)[^\s"']{8,}/i;
const PRIVATE_KEY_BLOCK = /-----BEGIN (?:RSA |EC |OPENSSH )?PRIVATE KEY-----/;

export function containsLikelySecret(value) {
  if (typeof value !== "string") throw new Error("secret policy input must be a string");
  return CREDENTIAL_PREFIX.test(value) || SENSITIVE_ASSIGNMENT.test(value) || PRIVATE_KEY_BLOCK.test(value);
}

export function evaluateSecretMaterial(invocation) {
  if (invocation.subjectKind === "command") {
    return containsLikelySecret(invocation.subject)
      ? block(SECRET_COMMAND_POLICY_ID, "command appears to contain secret material")
      : allow(SECRET_COMMAND_POLICY_ID);
  }
  if (invocation.subjectKind === "prompt") {
    return containsLikelySecret(invocation.subject)
      ? advisory(SECRET_PROMPT_POLICY_ID, "prompt appears to contain secret material; redact it before continuing")
      : allow(SECRET_PROMPT_POLICY_ID);
  }
  return allow(SECRET_COMMAND_POLICY_ID);
}
