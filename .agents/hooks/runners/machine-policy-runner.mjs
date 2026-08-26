import { normalizeClaudeInvocation, renderClaudePolicyResponse } from "../adapters/claude/index.mjs";
import { normalizeCodexInvocation, renderCodexPolicyResponse } from "../adapters/codex/index.mjs";
import { evaluateMachinePolicies } from "../policies/machine/index.mjs";
import { HOST_PRESSURE_GATE_ID, requiresHostPressureEvidence } from "../policies/machine/host-pressure.mjs";
import { readHostPressureEvidence } from "./host-pressure-evidence.mjs";

export const MACHINE_RUNNER_EFFECTS = Object.freeze({
  reads: Object.freeze(["stdin-hook-payload", "host.cpu-count", "host.load-average-1m", "host.memory"]),
  writes: Object.freeze(["stdout-native-response"]),
  network: false,
  persistence: false,
  telemetryFields: Object.freeze(["platform", "event", "verdict", "gateIds", "blockerIds", "advisoryIds", "elapsedMs"]),
});

function withTimeout(execute, timeoutMs) {
  return new Promise((resolve) => {
    let settled = false;
    const finish = (value) => {
      if (settled) return;
      settled = true;
      clearTimeout(timer);
      resolve(value);
    };
    const timer = setTimeout(() => finish({ ok: false, failure: "timeout" }), timeoutMs);
    Promise.resolve()
      .then(execute)
      .then(finish, () => finish({ ok: false, failure: "unavailable" }));
  });
}

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

export async function runMachinePolicies({
  platform,
  payload,
  trustedOverrides = new Set(),
  hostEvidenceReader = readHostPressureEvidence,
  evidenceTimeoutMs = 100,
  monotonicNow = () => performance.now(),
}) {
  if (!Number.isInteger(evidenceTimeoutMs) || evidenceTimeoutMs <= 0) {
    throw new Error("evidence timeout must be a positive integer");
  }
  const startedAt = monotonicNow();
  const invocation = normalize(platform, payload);
  const hostEvidence = requiresHostPressureEvidence(invocation) && !trustedOverrides.has(HOST_PRESSURE_GATE_ID)
    ? await withTimeout(hostEvidenceReader, evidenceTimeoutMs)
    : null;
  const composition = evaluateMachinePolicies(invocation, { hostEvidence, trustedOverrides });
  const response = render(platform, invocation.event, composition);
  const telemetry = Object.freeze({
    platform,
    event: invocation.event,
    verdict: composition.verdict,
    gateIds: composition.gateIds,
    blockerIds: composition.blockerIds,
    advisoryIds: Object.freeze(composition.advisories.map((item) => item.id)),
    elapsedMs: Math.max(0, monotonicNow() - startedAt),
  });
  return Object.freeze({ composition, response, telemetry });
}
