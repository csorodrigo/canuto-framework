const ROLES = new Set(["gate", "advisory"]);
const GATE_VERDICTS = new Set(["allow", "block"]);

function requireString(value, label) {
  if (typeof value !== "string" || value.length === 0) {
    throw new Error(`${label} must be a non-empty string`);
  }
  return value;
}

function requireDecision(value) {
  if (!value || typeof value !== "object" || Array.isArray(value)) {
    throw new Error("policy decision must be an object");
  }
  requireString(value.id, "policy decision id");
  requireString(value.reason, "policy decision reason");
  if (!ROLES.has(value.role)) throw new Error(`unsupported policy role ${value.role}`);
  if (value.role === "gate" && !GATE_VERDICTS.has(value.verdict)) {
    throw new Error(`unsupported Gate verdict ${value.verdict}`);
  }
  if (value.role === "advisory" && value.verdict !== "observe") {
    throw new Error("Advisory verdict must be observe");
  }
  return value;
}

export function allow(id, reason = "policy satisfied") {
  return { id: requireString(id, "policy id"), role: "gate", verdict: "allow", reason };
}

export function block(id, reason) {
  return {
    id: requireString(id, "policy id"),
    role: "gate",
    verdict: "block",
    reason: requireString(reason, "block reason"),
  };
}

export function advisory(id, reason) {
  return {
    id: requireString(id, "policy id"),
    role: "advisory",
    verdict: "observe",
    reason: requireString(reason, "advisory reason"),
  };
}

export function composePolicyResults(decisions) {
  if (!Array.isArray(decisions) || decisions.length === 0) {
    throw new Error("at least one policy decision is required");
  }
  const values = decisions.map(requireDecision);
  const gates = values.filter((item) => item.role === "gate");
  const advisories = values.filter((item) => item.role === "advisory");
  const blockers = gates.filter((item) => item.verdict === "block");
  return Object.freeze({
    verdict: blockers.length === 0 ? "allow" : "block",
    reason: blockers.map((item) => item.reason).join("; "),
    gateIds: Object.freeze(gates.map((item) => item.id)),
    blockerIds: Object.freeze(blockers.map((item) => item.id)),
    advisories: Object.freeze(advisories.map((item) => Object.freeze({ id: item.id, message: item.reason }))),
  });
}

