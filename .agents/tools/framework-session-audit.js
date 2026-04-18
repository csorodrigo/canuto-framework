#!/usr/bin/env node

const {
  parseArgs,
  runAudit,
  writeAuditOutputs,
} = require('./framework-session-audit-lib');

function printHelp() {
  console.log(`Canuto framework-session-audit

Usage:
  node .agents/tools/framework-session-audit.js \\
    --workspaces-root /Users/rodrigooliveira/conductor/workspaces \\
    --vault-root ~/.canuto/vault/projects \\
    --codex-log-roots ~/.codex/sessions ~/.codex/archived_sessions \\
    --claude-projects-root ~/.claude/projects \\
    --claude-telemetry-root ~/.claude/telemetry \\
    --pricing-path ~/.cache/codeburn/litellm-pricing.json \\
    --session-limit 200 \\
    --parallelism 4 \\
    --output-dir .context/audits/canuto-session-audit-YYYYMMDD

Options:
  --workspaces-root <path>   Root directory that contains Conductor workspaces.
  --vault-root <path>        Root directory of ~/.canuto/vault/projects.
  --codex-log-roots <paths>  One or more Codex session log roots.
  --claude-projects-root <path>
                             Root directory of Claude project JSONL logs. Default: ~/.claude/projects.
  --claude-telemetry-root <path>
                             Root directory of Claude telemetry JSON files. Default: ~/.claude/telemetry.
  --pricing-path <path>      LiteLLM/Codeburn pricing JSON. Default: ~/.cache/codeburn/litellm-pricing.json.
  --codeburn-export <path>   Optional Codeburn usage export JSON to merge as external observations.
  --session-limit <number>   Maximum sessions analyzed per project. Default: 200.
  --parallelism <number>     Concurrent project workers. Default: 4.
  --analysis-mode <mode>     deterministic | codex-reviewer. Default: deterministic.
  --output-dir <path>        Destination for inventory, dataset, report, and cost dashboard files.
  --help                     Show this help text.
`);
}

async function main() {
  if (process.argv.includes('--help')) {
    printHelp();
    return;
  }

  const options = parseArgs(process.argv.slice(2), process.cwd());
  const result = await runAudit(options);
  writeAuditOutputs(options.outputDir, result);

  const totalSessions = result.project_summaries.reduce(
    (sum, summary) => sum + summary.sessions_analyzed,
    0,
  );

  console.log(JSON.stringify({
    output_dir: options.outputDir,
    projects: result.project_summaries.length,
    sessions: totalSessions,
    generated_at: result.generated_at,
    analysis_mode: options.analysisMode,
  }, null, 2));
}

main().catch((error) => {
  console.error(error && error.stack ? error.stack : String(error));
  process.exitCode = 1;
});
