import { lstat, readFile, realpath } from "node:fs/promises";
import { join, relative, resolve, sep } from "node:path";

export const REPO_POLICY_MANIFEST = ".agents/hooks/manifest.json";
export const REPO_POLICY_IDS = Object.freeze([
  "worktree-dependencies",
  "build-typecheck",
  "claims",
  "branch-creation",
  "deploy-target",
  "validation-receipt",
  "commit",
  "pull-request",
]);

const POLICY_IDS = new Set(REPO_POLICY_IDS);
const TOP_LEVEL_KEYS = new Set(["$schema", "schemaVersion", "policies"]);
const POLICY_KEYS = new Set(["id", "options"]);

function result(manifestStatus, decision, details = {}) {
  return Object.freeze({ manifestStatus, decision, ...details });
}

function validateObjectKeys(value, allowed, at, errors) {
  for (const key of Object.keys(value)) {
    if (!allowed.has(key)) errors.push(`${at}.${key} is not allowed`);
  }
}

export function validateRepoPolicyManifest(value) {
  const errors = [];
  if (!value || typeof value !== "object" || Array.isArray(value)) {
    return ["manifest must be an object"];
  }
  validateObjectKeys(value, TOP_LEVEL_KEYS, "$", errors);
  if (value.$schema !== "./repo-policy.schema.json") {
    errors.push("$.$schema must equal ./repo-policy.schema.json");
  }
  if (value.schemaVersion !== 1) errors.push("$.schemaVersion must equal 1");
  if (!Array.isArray(value.policies)) {
    errors.push("$.policies must be an array");
    return errors;
  }

  const ids = new Set();
  value.policies.forEach((policy, index) => {
    const at = `$.policies[${index}]`;
    if (!policy || typeof policy !== "object" || Array.isArray(policy)) {
      errors.push(`${at} must be an object`);
      return;
    }
    validateObjectKeys(policy, POLICY_KEYS, at, errors);
    if (!POLICY_IDS.has(policy.id)) errors.push(`${at}.id is not a supported repository policy`);
    if (ids.has(policy.id)) errors.push(`${at}.id is duplicated`);
    ids.add(policy.id);
    if (Object.hasOwn(policy, "options") && (!policy.options || typeof policy.options !== "object" || Array.isArray(policy.options))) {
      errors.push(`${at}.options must be an object`);
    }
  });
  return errors;
}

async function manifestPathState(repoRoot) {
  const canonicalRoot = await realpath(resolve(repoRoot));
  const manifestPath = join(canonicalRoot, REPO_POLICY_MANIFEST);
  const manifestRelative = relative(canonicalRoot, manifestPath);
  if (!manifestRelative || manifestRelative === ".." || manifestRelative.startsWith(`..${sep}`)) {
    throw new Error("repository policy manifest escaped the repository root");
  }
  try {
    const state = await lstat(manifestPath);
    if (!state.isFile()) return { canonicalRoot, manifestPath, invalid: "manifest must be a regular file" };
    if (state.isSymbolicLink()) return { canonicalRoot, manifestPath, invalid: "manifest must not be a symlink" };
    const canonicalManifestPath = await realpath(manifestPath);
    if (canonicalManifestPath !== manifestPath) {
      return { canonicalRoot, manifestPath, invalid: "manifest path must not traverse symlinks" };
    }
    return { canonicalRoot, manifestPath };
  } catch (error) {
    if (error?.code === "ENOENT") return { canonicalRoot, manifestPath, absent: true };
    return { canonicalRoot, manifestPath, invalid: "manifest could not be inspected" };
  }
}

export async function loadRepoPolicyManifest({ repoRoot }) {
  const state = await manifestPathState(repoRoot);
  if (state.absent) return result("absent", "no-op", { manifestPath: state.manifestPath, policies: [] });
  if (state.invalid) return result("invalid", "block", { manifestPath: state.manifestPath, errors: [state.invalid] });

  let manifest;
  try {
    manifest = JSON.parse(await readFile(state.manifestPath, "utf8"));
  } catch {
    return result("invalid", "block", { manifestPath: state.manifestPath, errors: ["manifest must contain valid JSON"] });
  }
  const errors = validateRepoPolicyManifest(manifest);
  if (errors.length > 0) return result("invalid", "block", { manifestPath: state.manifestPath, errors });
  return result("valid", "no-op", {
    manifestPath: state.manifestPath,
    manifest: Object.freeze(manifest),
    policies: Object.freeze(manifest.policies.map((policy) => Object.freeze({ ...policy }))),
  });
}

export async function resolveRepoPolicy({ repoRoot, policyId }) {
  if (!POLICY_IDS.has(policyId)) throw new Error(`unsupported repository policy ${policyId}`);
  const loaded = await loadRepoPolicyManifest({ repoRoot });
  if (loaded.manifestStatus !== "valid") return loaded;
  const policy = loaded.policies.find((candidate) => candidate.id === policyId);
  if (!policy) return result("valid", "no-op", { manifestPath: loaded.manifestPath, policyId });
  return result("valid", "apply", { manifestPath: loaded.manifestPath, policyId, policy });
}
