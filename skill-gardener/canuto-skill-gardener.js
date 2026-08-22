#!/usr/bin/env node
'use strict';

const path = require('node:path');

let gardener;
try {
  gardener = require('./canuto-skill-gardener-lib');
} catch {
  gardener = require(path.join(__dirname, '..', 'lib', 'canuto-skill-gardener-lib'));
}

function help() {
  return `canuto-skill-gardener — deterministic weekly report-only skill audit

Usage:
  canuto-skill-gardener backfill [options]
  canuto-skill-gardener weekly [options]
  canuto-skill-gardener status [options]
  canuto-skill-gardener report --run <id> [--json]
  canuto-skill-gardener cron install|remove|status [--dry-run]
  canuto-skill-gardener canary status|record --run <id> [--post-merge]

Runtime overrides for tests and isolated canaries:
  --home <path>       HOME-like root for .canuto state
  --state-dir <path>  Cursor/lock state directory
  --config <path>     Skill gardener config JSON
  --vault-root <path> Private Canuto vault root
  --artifact-root <path>  Isolated report/receipt root
  --canary <path>      Isolated post-merge canary receipt
  --now <ISO>         Deterministic clock
`;
}

function parseArgs(argv) {
  const result = { command: '', subcommand: '', json: false, dryRun: false, unsupportedProject: false, options: {} };
  const valueFlags = {
    '--run': 'run',
    '--home': 'home',
    '--state-dir': 'stateDir',
    '--config': 'configPath',
    '--vault-root': 'vaultRoot',
    '--artifact-root': 'artifactRoot',
    '--canary': 'canaryPath',
    '--now': 'now',
  };
  const commonFlags = new Set(['--json', '--home', '--state-dir', '--vault-root', '--artifact-root', '--now']);
  const rows = {
    backfill: { values: new Set([...commonFlags, '--config']), booleans: new Set(['--json']), required: [] },
    weekly: { values: new Set([...commonFlags, '--config']), booleans: new Set(['--json']), required: [] },
    status: { values: new Set([...commonFlags, '--config']), booleans: new Set(['--json']), required: [] },
    report: { values: new Set([...commonFlags, '--run']), booleans: new Set(['--json']), required: ['--run'] },
    'cron:install': { values: new Set([...commonFlags, '--canary']), booleans: new Set(['--json', '--dry-run']), required: [] },
    'cron:remove': { values: new Set([...commonFlags, '--canary']), booleans: new Set(['--json', '--dry-run']), required: [] },
    'cron:status': { values: new Set([...commonFlags, '--canary']), booleans: new Set(['--json', '--dry-run']), required: [] },
    'canary:status': { values: new Set([...commonFlags, '--canary']), booleans: new Set(['--json']), required: [] },
    'canary:record': { values: new Set([...commonFlags, '--canary', '--run']), booleans: new Set(['--json', '--post-merge']), required: ['--run', '--post-merge'] },
  };

  const fail = (message) => ({ ...result, error: message });
  if (!Array.isArray(argv)) return fail('arguments must be an array');
  if (argv.length === 0 || (argv.length === 1 && (argv[0] === '--help' || argv[0] === '-h'))) return { ...result, help: true };
  if (argv.some((arg) => arg === '--help' || arg === '-h')) return fail('--help must be used alone');
  if (argv.some((arg) => arg === '--project' || String(arg).startsWith('--project='))) {
    result.unsupportedProject = true;
    return fail('--project is not supported; project scoping is unavailable');
  }

  let index = 0;
  const command = argv[index];
  if (!command || command.startsWith('-')) return fail('a command is required');
  result.command = command;
  index += 1;
  if (['cron', 'canary'].includes(command)) {
    const subcommand = argv[index];
    if (!subcommand || subcommand.startsWith('-')) return fail(`${command} requires a subcommand`);
    result.subcommand = subcommand;
    index += 1;
  }
  const row = rows[`${result.command}:${result.subcommand}`] || rows[result.command];
  if (!row) return fail(`unknown command: ${result.command}${result.subcommand ? ` ${result.subcommand}` : ''}`);

  const seenValues = new Set();
  while (index < argv.length) {
    const arg = argv[index++];
    if (typeof arg !== 'string' || !arg) return fail('empty argument');
    if (arg.includes('=') && arg.startsWith('--')) return fail(`unsupported option form: ${arg.split('=')[0]}`);
    if (arg === '--json' || arg === '--dry-run' || arg === '--post-merge') {
      if (!row.booleans.has(arg)) return fail(`option not allowed: ${arg}`);
      if (arg === '--json') result.json = true;
      else if (arg === '--dry-run') result.dryRun = true;
      else result.options.postMerge = true;
      continue;
    }
    if (Object.hasOwn(valueFlags, arg)) {
      if (!row.values.has(arg)) return fail(`option not allowed: ${arg}`);
      if (seenValues.has(arg)) return fail(`duplicate option: ${arg}`);
      const value = argv[index];
      if (value === undefined || value === '' || (typeof value === 'string' && value.startsWith('-'))) {
        return fail(`${arg} requires a value`);
      }
      seenValues.add(arg);
      result.options[valueFlags[arg]] = value;
      index += 1;
      continue;
    }
    if (arg.startsWith('-')) return fail(`unknown option: ${arg}`);
    return fail(`unexpected argument: ${arg}`);
  }
  for (const required of row.required) {
    if (required === '--post-merge' ? result.options.postMerge !== true : !result.options[valueFlags[required]]) {
      return fail(`${result.command}${result.subcommand ? ` ${result.subcommand}` : ''} requires ${required}${required === '--run' ? ' <id>' : ''}`);
    }
  }
  return result;
}

function printJson(value) {
  process.stdout.write(`${JSON.stringify(value, null, 2)}\n`);
}

function runtimeFrom(options) {
  return gardener.getRuntimeOptions(options);
}

async function main(argv = process.argv.slice(2)) {
  const args = parseArgs(argv);
  if (args.help) {
    process.stdout.write(help());
    return 0;
  }
  if (args.error) {
    process.stderr.write(`Argument error: ${args.error}.\n`);
    return 1;
  }
  if (args.command === 'status') {
    const status = gardener.statusJson(runtimeFrom({ ...args.options, readOnly: true }));
    if (args.json) printJson(status);
    else process.stdout.write(`${status.status} ${status.latestRunId || '(no run)'}\n`);
    return status.status === 'UNAVAILABLE' ? 1 : 0;
  }
  if (args.command === 'report') {
    if (!args.options.run) {
      process.stderr.write('report requires --run <id>\n');
      return 1;
    }
    const report = gardener.reportForRun(runtimeFrom({ ...args.options, readOnly: true }), args.options.run);
    if (!report) {
      process.stderr.write(`run not found: ${args.options.run}\n`);
      return 1;
    }
    if (args.json) printJson(report);
    else process.stdout.write(report.markdown || `${JSON.stringify(report, null, 2)}\n`);
    return report.status === 'partial' ? 2 : 0;
  }
  if (args.command === 'cron') {
    if (!['install', 'remove', 'status'].includes(args.subcommand)) {
      process.stderr.write('cron requires install, remove, or status\n');
      return 1;
    }
    const result = gardener.cronAction(args.subcommand, { ...args.options, dryRun: args.dryRun || args.subcommand === 'status' });
    const output = {
      schemaVersion: 1,
      tool: 'canuto-skill-gardener',
      action: args.subcommand,
      dryRun: args.dryRun || args.subcommand === 'status',
      changed: result.changed,
      installed: result.installed,
      status: result.status || (result.ok ? 'READY' : 'UNAVAILABLE'),
      line: result.line,
      preview: result.next,
      reason: result.reason || '',
      canaryStatus: result.canaryStatus || '',
    };
    if (args.json) printJson(output);
    else {
      const detail = result.status === 'UNAVAILABLE'
        ? 'unavailable'
        : args.subcommand === 'status' ? result.installed ? 'installed' : 'not installed' : result.next;
      process.stdout.write(`${args.subcommand}: ${result.changed ? 'changed' : 'unchanged'}\n${detail}`);
    }
    return result.ok ? 0 : 1;
  }
  if (args.command === 'canary') {
    const runtime = args.subcommand === 'record'
      ? runtimeFrom({ ...args.options, runId: args.options.run })
      : runtimeFrom({ ...args.options, readOnly: true });
    const result = args.subcommand === 'status'
      ? gardener.canaryStatus(runtime)
      : gardener.recordCanaryReceipt(runtime);
    if (args.json) printJson({ schemaVersion: 1, tool: 'canuto-skill-gardener', action: `canary:${args.subcommand}`, ...result });
    else process.stdout.write(`${args.subcommand}: ${result.ok ? result.status || 'ok' : result.reason || 'blocked'}\n`);
    return result.ok ? 0 : 1;
  }
  const result = await gardener.runGardener(args.command, args.options);
  if (args.json) printJson({ schemaVersion: 1, tool: 'canuto-skill-gardener', runId: result.runId, status: result.status, exitCode: result.exitCode });
  else if (result.report) process.stdout.write(`${result.report.markdown || ''}`);
  else if (result.error) process.stderr.write(`${result.error}\n`);
  return result.exitCode;
}

if (require.main === module) {
  main().then((code) => { process.exitCode = code; }).catch((error) => {
    process.stderr.write(`${error && error.stack ? error.stack : String(error)}\n`);
    process.exitCode = 1;
  });
}

module.exports = { help, main, parseArgs };
