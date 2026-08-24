'use strict';

const assert = require('node:assert/strict');
const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');
const test = require('node:test');
const {
  applyBundle,
  buildPlan,
  fingerprintDirectory,
  resolveBundle,
  rollbackReceipt,
  verifyBundle,
  writeJsonAtomic,
} = require('./skill-bundle-publisher.js');

function fixture() {
  const root = fs.mkdtempSync(path.join(os.tmpdir(), 'canuto-skill-publisher-'));
  const target = path.join(root, 'target', 'skills');
  const manifestFile = path.join(root, 'repository', 'distribution', 'fixture.json');
  const skillsRoot = path.join(root, 'repository', 'global-skills');
  fs.mkdirSync(path.join(skillsRoot, 'alpha'), { recursive: true });
  fs.mkdirSync(path.join(skillsRoot, 'beta'), { recursive: true });
  fs.writeFileSync(path.join(skillsRoot, 'alpha', 'SKILL.md'), '# alpha\n');
  fs.writeFileSync(path.join(skillsRoot, 'beta', 'SKILL.md'), '# beta\n');

  function writeManifest(ref = '1111111111111111111111111111111111111111') {
    writeJsonAtomic(manifestFile, {
      schemaVersion: 1,
      bundleId: 'fixture',
      source: { repository: 'fixture', ref },
      skills: ['alpha', 'beta'].map((name) => ({
        name,
        upstreamPath: `skills/${name}`,
        sha256: fingerprintDirectory(path.join(skillsRoot, name)),
      })),
    });
  }
  writeManifest();
  return {
    root,
    target,
    manifestFile,
    skillsRoot,
    writeManifest,
    cleanup: () => fs.rmSync(root, { recursive: true, force: true }),
  };
}

test('apply, verify and recoverable rollback for new skills', () => {
  const data = fixture();
  try {
    const bundle = resolveBundle(data.manifestFile);
    const plan = buildPlan(bundle, data.target);
    assert.equal(plan.changes, 2);
    assert.equal(plan.conflicts, 0);
    const receipt = applyBundle(bundle, data.target);
    assert.equal(receipt.actions.filter((item) => item.action === 'CREATE').length, 2);
    assert.equal(verifyBundle(bundle, data.target).ok, true);

    const rollback = rollbackReceipt(receipt.receiptFile);
    assert.equal(fs.existsSync(path.join(data.target, 'alpha')), false);
    assert.equal(fs.existsSync(path.join(rollback.archiveRoot, 'alpha')), true);
  } finally {
    data.cleanup();
  }
});

test('apply refuses every mutation when an unmanaged conflict exists', () => {
  const data = fixture();
  try {
    fs.mkdirSync(path.join(data.target, 'beta'), { recursive: true });
    fs.writeFileSync(path.join(data.target, 'beta', 'SKILL.md'), '# customized beta\n');
    const bundle = resolveBundle(data.manifestFile);
    assert.equal(buildPlan(bundle, data.target).conflicts, 1);
    assert.throws(() => applyBundle(bundle, data.target), /unmanaged conflict/);
    assert.equal(fs.existsSync(path.join(data.target, 'alpha')), false);
    assert.equal(fs.readFileSync(path.join(data.target, 'beta', 'SKILL.md'), 'utf8'), '# customized beta\n');
  } finally {
    data.cleanup();
  }
});

test('identical directories are adopted without content replacement', () => {
  const data = fixture();
  try {
    fs.cpSync(path.join(data.skillsRoot, 'alpha'), path.join(data.target, 'alpha'), { recursive: true });
    fs.cpSync(path.join(data.skillsRoot, 'beta'), path.join(data.target, 'beta'), { recursive: true });
    const before = fs.statSync(path.join(data.target, 'alpha', 'SKILL.md')).ino;
    const receipt = applyBundle(resolveBundle(data.manifestFile), data.target);
    assert.equal(receipt.actions.every((item) => item.action === 'IDENTICAL'), true);
    assert.equal(fs.statSync(path.join(data.target, 'alpha', 'SKILL.md')).ino, before);
  } finally {
    data.cleanup();
  }
});

test('managed update backs up the old version and rollback restores it', () => {
  const data = fixture();
  try {
    const first = applyBundle(resolveBundle(data.manifestFile), data.target);
    assert.equal(verifyBundle(resolveBundle(data.manifestFile), data.target).ok, true);
    fs.writeFileSync(path.join(data.skillsRoot, 'alpha', 'SKILL.md'), '# alpha v2\n');
    data.writeManifest('2222222222222222222222222222222222222222');

    const second = applyBundle(resolveBundle(data.manifestFile), data.target);
    const alpha = second.actions.find((item) => item.name === 'alpha');
    assert.equal(alpha.action, 'UPDATE');
    assert.equal(fs.readFileSync(path.join(data.target, 'alpha', 'SKILL.md'), 'utf8'), '# alpha v2\n');
    rollbackReceipt(second.receiptFile);
    assert.equal(fs.readFileSync(path.join(data.target, 'alpha', 'SKILL.md'), 'utf8'), '# alpha\n');
    assert.equal(fs.existsSync(first.receiptFile), true);
  } finally {
    data.cleanup();
  }
});

test('manifest fingerprint prevents publishing a tampered source', () => {
  const data = fixture();
  try {
    fs.appendFileSync(path.join(data.skillsRoot, 'alpha', 'SKILL.md'), 'tampered\n');
    assert.throws(() => resolveBundle(data.manifestFile), /Source fingerprint mismatch/);
  } finally {
    data.cleanup();
  }
});

test('publisher refuses a broad or ambiguous target root', () => {
  const data = fixture();
  try {
    const bundle = resolveBundle(data.manifestFile);
    assert.throws(() => buildPlan(bundle, path.join(data.root, 'not-a-provider-root')), /provider skills directory/);
  } finally {
    data.cleanup();
  }
});

test('manifest rejects a traversal bundle id', () => {
  const data = fixture();
  try {
    const manifest = JSON.parse(fs.readFileSync(data.manifestFile, 'utf8'));
    manifest.bundleId = '../../../../tmp/escaped';
    writeJsonAtomic(data.manifestFile, manifest);
    assert.throws(() => resolveBundle(data.manifestFile), /Unsupported skill bundle manifest/);
  } finally {
    data.cleanup();
  }
});

test('failed update rename restores the prior managed skill', () => {
  const data = fixture();
  const originalRename = fs.renameSync;
  try {
    applyBundle(resolveBundle(data.manifestFile), data.target);
    fs.writeFileSync(path.join(data.skillsRoot, 'alpha', 'SKILL.md'), '# alpha v2\n');
    data.writeManifest('2222222222222222222222222222222222222222');
    let injected = false;
    fs.renameSync = (source, destination) => {
      if (!injected
        && source.includes(`${path.sep}staging${path.sep}`)
        && destination === path.join(data.target, 'alpha')) {
        injected = true;
        throw new Error('injected final rename failure');
      }
      return originalRename(source, destination);
    };
    assert.throws(() => applyBundle(resolveBundle(data.manifestFile), data.target), /injected final rename failure/);
    assert.equal(fs.readFileSync(path.join(data.target, 'alpha', 'SKILL.md'), 'utf8'), '# alpha\n');
  } finally {
    fs.renameSync = originalRename;
    data.cleanup();
  }
});

test('rollback rejects a forged destination before moving any skill', () => {
  const data = fixture();
  try {
    const receipt = applyBundle(resolveBundle(data.manifestFile), data.target);
    const forged = JSON.parse(fs.readFileSync(receipt.receiptFile, 'utf8'));
    forged.actions[0].destination = path.join(data.root, 'outside', forged.actions[0].name);
    const forgedFile = path.join(data.root, 'forged-receipt.json');
    writeJsonAtomic(forgedFile, forged);
    assert.throws(() => rollbackReceipt(forgedFile), /Invalid action in apply receipt/);
    assert.equal(verifyBundle(resolveBundle(data.manifestFile), data.target).ok, true);
  } finally {
    data.cleanup();
  }
});
