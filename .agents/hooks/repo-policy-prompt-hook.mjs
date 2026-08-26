#!/usr/bin/env node

// Event-specific entrypoint; evaluator ownership stays in repo-policy-hook.mjs.
await import("./repo-policy-hook.mjs");
