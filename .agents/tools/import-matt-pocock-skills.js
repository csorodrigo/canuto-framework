#!/usr/bin/env node
'use strict';

const fs = require('node:fs');
const path = require('node:path');
const { execFileSync } = require('node:child_process');
const {
  fingerprintDirectory,
  writeJsonAtomic,
} = require('./skill-bundle-publisher.js');

function fail(message) {
  throw new Error(message);
}

function parseArgs(argv) {
  const options = {};
  for (let index = 0; index < argv.length; index += 1) {
    const argument = argv[index];
    if (!argument.startsWith('--')) fail(`Unexpected argument: ${argument}`);
    const value = argv[index + 1];
    if (!value || value.startsWith('--')) fail(`Missing value for ${argument}`);
    options[argument.slice(2)] = value;
    index += 1;
  }
  if (!options.source || !options.ref) fail('Usage: import-matt-pocock-skills.js --source <checkout> --ref <commit-sha>');
  if (!/^[a-f0-9]{40}$/.test(options.ref)) fail('--ref must be an exact 40-character commit SHA');
  return options;
}

function git(checkout, ...args) {
  return execFileSync('git', ['-C', checkout, ...args], { encoding: 'utf8' }).trim();
}

function findSkillDirectories(skillsRoot, current = '') {
  const absolute = path.join(skillsRoot, current);
  const entries = fs.readdirSync(absolute, { withFileTypes: true });
  const found = [];
  if (entries.some((entry) => entry.isFile() && entry.name === 'SKILL.md')) found.push(absolute);
  for (const entry of entries) {
    if (entry.isDirectory()) {
      const relative = current ? path.join(current, entry.name) : entry.name;
      found.push(...findSkillDirectories(skillsRoot, relative));
    }
  }
  return found;
}

function main(argv = process.argv.slice(2)) {
  const options = parseArgs(argv);
  const source = path.resolve(options.source);
  const repositoryRoot = path.resolve(__dirname, '..', '..');
  const skillsRoot = path.join(source, 'skills');
  const manifestFile = path.join(repositoryRoot, 'distribution', 'matt-pocock-skills.json');
  const priorManifest = fs.existsSync(manifestFile)
    ? JSON.parse(fs.readFileSync(manifestFile, 'utf8'))
    : { skills: [] };
  const priorNames = new Set((priorManifest.skills || []).map((skill) => skill.name));

  if (!fs.existsSync(skillsRoot)) fail(`Upstream skills directory not found: ${skillsRoot}`);
  const head = git(source, 'rev-parse', 'HEAD');
  if (head !== options.ref) fail(`Checkout HEAD ${head} does not match requested ref ${options.ref}`);
  if (git(source, 'status', '--porcelain')) fail('Upstream checkout is dirty');
  const remote = git(source, 'remote', 'get-url', 'origin');
  if (!/^(?:https:\/\/github\.com\/|git@github\.com:)mattpocock\/skills(?:\.git)?$/.test(remote)) {
    fail(`Unexpected upstream remote: ${remote}`);
  }
  const licenseSource = path.join(source, 'LICENSE');
  if (!fs.existsSync(licenseSource)) fail('Upstream LICENSE is missing');

  const directories = findSkillDirectories(skillsRoot);
  const byName = new Map();
  for (const directory of directories) {
    const name = path.basename(directory);
    if (!/^[a-z0-9][a-z0-9-]*$/.test(name)) fail(`Invalid upstream skill name: ${name}`);
    if (byName.has(name)) fail(`Duplicate upstream skill name: ${name}`);
    byName.set(name, directory);
  }

  const stagingRoot = fs.mkdtempSync(path.join(repositoryRoot, '.matt-skills-import-'));
  const replaced = [];
  try {
    for (const [name, directory] of [...byName.entries()].sort()) {
      const destination = path.join(repositoryRoot, 'global-skills', name);
      const incoming = path.join(stagingRoot, name);
      fs.cpSync(directory, incoming, { recursive: true, errorOnExist: true, force: false });
      let previous = null;
      if (fs.existsSync(destination)) {
        const unchanged = fingerprintDirectory(destination) === fingerprintDirectory(incoming);
        if (!priorNames.has(name) && !unchanged) fail(`Refusing to replace non-bundle global skill: ${name}`);
        if (unchanged) continue;
        previous = path.join(stagingRoot, '.previous', name);
        fs.mkdirSync(path.dirname(previous), { recursive: true });
        fs.renameSync(destination, previous);
        replaced.push({ destination, previous });
      }
      fs.renameSync(incoming, destination);
      if (!previous) replaced.push({ destination, previous });
    }
    for (const priorSkill of priorManifest.skills || []) {
      if (byName.has(priorSkill.name)) continue;
      const destination = path.join(repositoryRoot, 'global-skills', priorSkill.name);
      if (!fs.existsSync(destination)) continue;
      if (fingerprintDirectory(destination) !== priorSkill.sha256) {
        fail(`Refusing to remove modified bundle skill: ${priorSkill.name}`);
      }
      const previous = path.join(stagingRoot, '.previous', priorSkill.name);
      fs.mkdirSync(path.dirname(previous), { recursive: true });
      fs.renameSync(destination, previous);
      replaced.push({ destination, previous });
    }
  } catch (error) {
    for (const item of [...replaced].reverse()) {
      if (fs.existsSync(item.destination)) {
        const failed = path.join(stagingRoot, '.failed', path.basename(item.destination));
        fs.mkdirSync(path.dirname(failed), { recursive: true });
        fs.renameSync(item.destination, failed);
      }
      if (item.previous && fs.existsSync(item.previous)) fs.renameSync(item.previous, item.destination);
    }
    throw error;
  } finally {
    fs.rmSync(stagingRoot, { recursive: true, force: true });
  }

  const licenseDestination = path.join(repositoryRoot, 'distribution', 'licenses', 'matt-pocock-skills.LICENSE');
  fs.mkdirSync(path.dirname(licenseDestination), { recursive: true });
  fs.copyFileSync(licenseSource, licenseDestination);

  const skills = [...byName.entries()].sort().map(([name, directory]) => ({
    name,
    upstreamPath: path.relative(source, directory).split(path.sep).join('/'),
    sha256: fingerprintDirectory(path.join(repositoryRoot, 'global-skills', name)),
  }));
  const manifest = {
    schemaVersion: 1,
    bundleId: 'matt-pocock-skills',
    source: {
      repository: 'https://github.com/mattpocock/skills',
      ref: options.ref,
      license: 'MIT',
      licenseFile: 'distribution/licenses/matt-pocock-skills.LICENSE',
    },
    skills,
  };
  writeJsonAtomic(manifestFile, manifest);
  process.stdout.write(`${JSON.stringify({ manifestFile, sourceRef: options.ref, skills: skills.length }, null, 2)}\n`);
}

if (require.main === module) {
  try {
    main();
  } catch (error) {
    process.stderr.write(`${error.message}\n`);
    process.exitCode = 1;
  }
}

module.exports = { findSkillDirectories, main, parseArgs };
