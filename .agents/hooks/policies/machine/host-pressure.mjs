import { advisory, allow, block } from "../../core/policy-result.mjs";

export const HOST_PRESSURE_GATE_ID = "machine.host-pressure";
export const HOST_PRESSURE_ADVISORY_ID = "machine.host-pressure-advisory";

const RESOURCE_INTENSIVE = /(?:\b(?:npm|pnpm|yarn|bun)\s+(?:run\s+)?(?:build|test|typecheck|dev)\b|\bnext\s+(?:build|dev)\b|\btsc\b|\bpytest\b|\bcargo\s+(?:build|test)\b|\bxcodebuild\b|\bdocker\s+(?:build|compose)\b)/i;

export function requiresHostPressureEvidence(invocation) {
  return invocation.subjectKind === "command" && RESOURCE_INTENSIVE.test(invocation.subject);
}

function validEvidence(evidence) {
  return evidence
    && evidence.ok === true
    && Number.isFinite(evidence.availableMemoryPercent)
    && evidence.availableMemoryPercent >= 0
    && Number.isFinite(evidence.loadAverage1m)
    && evidence.loadAverage1m >= 0
    && Number.isInteger(evidence.cpuCount)
    && evidence.cpuCount > 0;
}

export function evaluateHostPressure(invocation, evidence, { trustedOverrides = new Set() } = {}) {
  if (!requiresHostPressureEvidence(invocation)) {
    return [allow(HOST_PRESSURE_GATE_ID)];
  }
  if (trustedOverrides.has(HOST_PRESSURE_GATE_ID)) {
    return [allow(HOST_PRESSURE_GATE_ID, "trusted override supplied out of band")];
  }
  if (!validEvidence(evidence)) {
    return [
      block(HOST_PRESSURE_GATE_ID, "host pressure evidence is unavailable"),
      advisory(HOST_PRESSURE_ADVISORY_ID, "host pressure could not be measured"),
    ];
  }
  const loadPerCpu = evidence.loadAverage1m / evidence.cpuCount;
  if (evidence.availableMemoryPercent < 6 && loadPerCpu > 2) {
    return [
      block(HOST_PRESSURE_GATE_ID, "host pressure is above the safe execution threshold"),
      advisory(HOST_PRESSURE_ADVISORY_ID, "defer resource-intensive work until host pressure falls"),
    ];
  }
  if (evidence.availableMemoryPercent < 12 || loadPerCpu > 1.5) {
    return [
      allow(HOST_PRESSURE_GATE_ID),
      advisory(HOST_PRESSURE_ADVISORY_ID, "host pressure is elevated; prefer a lighter validation path"),
    ];
  }
  return [allow(HOST_PRESSURE_GATE_ID)];
}
