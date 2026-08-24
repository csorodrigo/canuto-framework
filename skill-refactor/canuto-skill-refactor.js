#!/usr/bin/env node
'use strict';

const path = require('node:path');
const lib = require('./canuto-skill-refactor-lib');

function help() {
  return `canuto-skill-refactor — resumable isolated bulk skill estate compiler

Usage:
  canuto-skill-refactor --help
  canuto-skill-refactor --json doctor
  canuto-skill-refactor --json scan --workspace <dir> [--config <path>]
  canuto-skill-refactor --json queue --workspace <dir>
  canuto-skill-refactor --json run --workspace <dir> [--workers 1..4] [--limit N] [--resume]
  canuto-skill-refactor --json validate --workspace <dir>
  canuto-skill-refactor --json preview --workspace <dir> --name <skill>

The compiler only stages isolated candidates. It never applies, deletes, archives,
symlinks, installs, or modifies a live skill.
`;
}

const VALUE_FLAGS = new Set(['--workspace', '--config', '--workers', '--limit', '--name']);
const BOOLEAN_FLAGS = new Set(['--json', '--resume']);
const COMMANDS = new Set(['doctor', 'scan', 'queue', 'run', 'validate', 'preview']);
const COMMAND_SPECS = {
  doctor: { values: new Set(), booleans: new Set(['--json']), required: [] },
  scan: { values: new Set(['--workspace', '--config']), booleans: new Set(['--json']), required: ['--workspace'] },
  queue: { values: new Set(['--workspace']), booleans: new Set(['--json']), required: ['--workspace'] },
  run: { values: new Set(['--workspace', '--workers', '--limit']), booleans: new Set(['--json', '--resume']), required: ['--workspace'] },
  validate: { values: new Set(['--workspace']), booleans: new Set(['--json']), required: ['--workspace'] },
  preview: { values: new Set(['--workspace', '--name']), booleans: new Set(['--json']), required: ['--workspace', '--name'] },
};

function parseArgs(argv) {
  const result = { command: '', json: false, options: {}, help: false };
  if (!Array.isArray(argv)) return { ...result, error: { code: 'arguments-invalid', message: 'arguments must be an array' } };
  if (argv.length === 0) return { ...result, help: true };

  let jsonSeen = 0;
  for (const argument of argv) {
    if (argument === '--json') jsonSeen += 1;
  }
  result.json = jsonSeen > 0;
  if (jsonSeen > 1) return { ...result, error: { code: 'duplicate-option', message: 'duplicate option: --json' } };
  if (argv.some((argument) => argument === '--help' || argument === '-h')) {
    if (argv.length === 1 && (argv[0] === '--help' || argv[0] === '-h')) return { ...result, help: true };
    return { ...result, error: { code: 'help-must-be-alone', message: '--help must be used alone' } };
  }

  const args = argv.filter((argument) => argument !== '--json');
  const command = args.shift();
  if (!command || command.startsWith('-')) return { ...result, error: { code: 'command-required', message: 'a command is required' } };
  if (!COMMANDS.has(command)) return { ...result, command, error: { code: 'unknown-command', message: `unknown command: ${command}` } };
  result.command = command;
  const spec = COMMAND_SPECS[command];
  const seen = new Set();
  let index = 0;
  while (index < args.length) {
    const argument = args[index];
    if (typeof argument !== 'string' || !argument) return { ...result, error: { code: 'argument-invalid', message: 'empty argument' } };
    if (argument.includes('=') && argument.startsWith('--')) {
      return { ...result, error: { code: 'unsupported-option-form', message: `unsupported option form: ${argument.split('=')[0]}` } };
    }
    if (BOOLEAN_FLAGS.has(argument)) {
      if (!spec.booleans.has(argument)) return { ...result, error: { code: 'option-not-allowed', message: `option not allowed: ${argument}` } };
      if (seen.has(argument)) return { ...result, error: { code: 'duplicate-option', message: `duplicate option: ${argument}` } };
      seen.add(argument);
      if (argument === '--resume') result.options.resume = true;
      index += 1;
      continue;
    }
    if (VALUE_FLAGS.has(argument)) {
      if (!spec.values.has(argument)) return { ...result, error: { code: 'option-not-allowed', message: `option not allowed: ${argument}` } };
      if (seen.has(argument)) return { ...result, error: { code: 'duplicate-option', message: `duplicate option: ${argument}` } };
      const value = args[index + 1];
      if (value === undefined || value === '' || String(value).startsWith('-')) return { ...result, error: { code: 'option-value-required', message: `${argument} requires a value` } };
      seen.add(argument);
      result.options[argument.slice(2)] = value;
      index += 2;
      continue;
    }
    if (argument.startsWith('-')) return { ...result, error: { code: 'unknown-option', message: `unknown option: ${argument}` } };
    return { ...result, error: { code: 'unexpected-argument', message: `unexpected argument: ${argument}` } };
  }
  for (const required of spec.required) {
    if (!result.options[required.slice(2)]) return { ...result, error: { code: 'required-option-missing', message: `${command} requires ${required} <value>` } };
  }
  if (result.options.workspace !== undefined && !path.isAbsolute(result.options.workspace)) {
    return { ...result, error: { code: 'workspace-absolute-required', message: 'workspace must be an absolute path' } };
  }
  if (result.options.workers !== undefined && (!/^\d+$/.test(result.options.workers) || Number(result.options.workers) < 1 || Number(result.options.workers) > lib.MAX_WORKERS)) {
    return { ...result, error: { code: 'workers-invalid', message: `workers must be an integer from 1 to ${lib.MAX_WORKERS}` } };
  }
  if (result.options.limit !== undefined && (!/^\d+$/.test(result.options.limit) || Number(result.options.limit) < 1 || !Number.isSafeInteger(Number(result.options.limit)))) {
    return { ...result, error: { code: 'limit-invalid', message: 'limit must be a positive integer' } };
  }
  if (command === 'preview' && !lib.normalizeName(result.options.name)) return { ...result, error: { code: 'name-invalid', message: 'name must contain a logical skill name' } };
  return result;
}

function errorPayload(command, error) {
  const code = error?.code || error?.message || 'operation-failed';
  const message = error instanceof lib.RefactorError ? error.message : error?.message || String(error);
  return {
    schemaVersion: lib.SCHEMA_VERSION,
    tool: lib.TOOL,
    command: command || '',
    status: 'ERROR',
    error: { code, message },
  };
}

function printJson(value) {
  process.stdout.write(`${JSON.stringify(value, null, 2)}\n`);
}

function progress(message) {
  process.stderr.write(`[${lib.TOOL}] ${message}\n`);
}

async function main(argv = process.argv.slice(2)) {
  const args = parseArgs(argv);
  if (args.help) {
    process.stdout.write(help());
    return 0;
  }
  if (args.error) {
    if (args.json) printJson(errorPayload(args.command, args.error));
    else process.stderr.write(`Argument error: ${args.error.message}.\n`);
    return 2;
  }

  let result;
  try {
    if (args.command === 'doctor') {
      result = lib.doctor();
    } else if (args.command === 'scan') {
      progress('scanning configured skill roots');
      result = lib.scanWorkspace({
        workspace: args.options.workspace,
        configPath: args.options.config,
        frameworkRoot: process.env.CANUTO_SKILL_REFACTOR_FRAMEWORK_ROOT || process.env.CANUTO_SKILL_GARDENER_FRAMEWORK_ROOT || lib.defaultFrameworkRoot(),
      });
      result = {
        schemaVersion: lib.SCHEMA_VERSION,
        tool: lib.TOOL,
        command: 'scan',
        status: result.status,
        changed: result.changed,
        scanFingerprint: result.manifest.scanFingerprint,
        counts: result.manifest.counts,
      };
    } else if (args.command === 'queue') {
      result = { command: 'queue', ...lib.queueWorkspace(args.options.workspace) };
    } else if (args.command === 'run') {
      progress('running isolated refactor work items');
      result = { command: 'run', ...(await lib.runWorkspace({
        workspace: args.options.workspace,
        workers: args.options.workers === undefined ? 2 : Number(args.options.workers),
        limit: args.options.limit === undefined ? undefined : Number(args.options.limit),
        resume: args.options.resume === true,
        onProgress: progress,
      })) };
    } else if (args.command === 'validate') {
      progress('validating candidates and live source hashes');
      result = { command: 'validate', ...lib.validateWorkspace({ workspace: args.options.workspace }) };
    } else if (args.command === 'preview') {
      result = { command: 'preview', ...lib.previewWorkspace(args.options.workspace, args.options.name) };
    }
  } catch (error) {
    const payload = errorPayload(args.command, error);
    if (args.json) printJson(payload);
    else process.stderr.write(`${payload.error.message}\n`);
    return 2;
  }

  const exitCode = Number.isInteger(result.exitCode) ? result.exitCode : (result.status === 'BLOCKED' ? 2 : 0);
  delete result.exitCode;
  if (args.json) printJson(result);
  else {
    if (args.command === 'doctor') process.stdout.write(`doctor: ${result.status}\n`);
    else if (args.command === 'scan') process.stdout.write(`scan: ${result.changed ? 'staged' : 'unchanged'}\n`);
    else if (args.command === 'queue') process.stdout.write(`queue: ${result.counts.total} logical skills\n`);
    else if (args.command === 'run') process.stdout.write(`run: ${result.status.toLowerCase()} (${result.claimed} claimed)\n`);
    else if (args.command === 'validate') process.stdout.write(`validate: ${result.status.toLowerCase()}\n`);
    else if (args.command === 'preview') process.stdout.write(`${result.name}: ${result.classification} (${result.state})\n${result.nextCommand}\n`);
  }
  return exitCode;
}

if (require.main === module) {
  main().then((code) => { process.exitCode = code; }).catch((error) => {
    const payload = errorPayload('', error);
    if (process.argv.includes('--json')) printJson(payload);
    else process.stderr.write(`${payload.error.message}\n`);
    process.exitCode = 2;
  });
}

module.exports = { help, parseArgs, main };
