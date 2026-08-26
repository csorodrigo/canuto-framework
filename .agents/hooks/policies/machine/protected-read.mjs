import { allow, block } from "../../core/policy-result.mjs";

export const PROTECTED_READ_POLICY_ID = "machine.protected-read";

const READ_OPERATION = /(?:^|[;&|]\s*|\b)(?:cat|tac|head|tail|less|more|bat|sed|awk|strings|xxd|hexdump|base64|openssl\s+(?:pkey|rsa)|grep|rg)\b/i;
const SECRET_STORE_READ = /\b(?:security\s+find-(?:generic|internet)-password\b[^;&|]*\s-w\b|pass\s+(?:show|cat)\b|op\s+read\b)/i;
const PROTECTED_PATH = /(?:^|[\s'"=])(?:[^\s'";|]*\/)?(?:\.env(?:\.[A-Za-z0-9_-]+)?|id_(?:rsa|dsa|ecdsa|ed25519)|[^\s/'"]+\.(?:pem|key|p12|pfx)|credentials(?:\.json)?)(?=$|[\s'";|])/i;
const SAFE_TEMPLATE = /(?:\.env\.(?:example|sample|template)|\.pem\.(?:example|sample|template)|\.key\.(?:example|sample|template))(?=$|[\s'";|])/gi;

export function evaluateProtectedRead(invocation) {
  if (invocation.subjectKind !== "command") return allow(PROTECTED_READ_POLICY_ID);
  const command = invocation.subject;
  const readsSecretStore = SECRET_STORE_READ.test(command);
  const inspectedCommand = command.replace(SAFE_TEMPLATE, "");
  const readsProtectedPath = READ_OPERATION.test(command) && PROTECTED_PATH.test(inspectedCommand);
  return readsSecretStore || readsProtectedPath
    ? block(PROTECTED_READ_POLICY_ID, "reading protected environment or key material is not allowed")
    : allow(PROTECTED_READ_POLICY_ID);
}
