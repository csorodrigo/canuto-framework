// Testes de regressão do glossary-gate.
//
// Rodar: node --test .agents/tools/__tests__/
//
// Cada teste monta um repositório git descartável em tmpdir, escreve um
// CONTEXT.md mínimo e exercita o gate como PROCESSO (spawn), não como módulo —
// o contrato do gate é a CLI: exit code + stdout. Testar por import esconderia
// exatamente a classe de bug que já aconteceu (arquivo binário para o git).
//
// Os três incidentes desta ferramenta viram casos aqui, nomeados:
//   1. sentinela NUL tornava o próprio .mjs binário → "o gate é texto para o git"
//   2. diacríticos com caracteres combinantes literais → "normalização de acento"
//   3. continuação de JSDoc lida como código → "JSDoc não é código"

import { test } from "node:test";
import assert from "node:assert/strict";
import { execFileSync, spawnSync } from "node:child_process";
import { mkdtempSync, writeFileSync, mkdirSync, readFileSync, rmSync } from "node:fs";
import { tmpdir } from "node:os";
import { join, dirname, resolve } from "node:path";
import { fileURLToPath } from "node:url";

const GATE = resolve(dirname(fileURLToPath(import.meta.url)), "..", "glossary-gate.mjs");

const GLOSSARY = `# Projeto de Teste

## Linguagem

**Merchant**:
A loja individual cadastrada na plataforma.
_Evitar_: store, loja (só como tradução de UI), filial

**Delivery**:
A entrega de um pedido.
_Evitar_: entrega (só como tradução de UI)

**Review**:
A avaliação inteira.
_Evitar_: avaliação (só como tradução de UI)
`;

function sh(cwd, cmd, args) {
  return execFileSync(cmd, args, { cwd, encoding: "utf8" });
}

/** Repo git descartável com CONTEXT.md e um commit-base. */
function makeRepo(t) {
  const dir = mkdtempSync(join(tmpdir(), "gg-test-"));
  t.after(() => rmSync(dir, { recursive: true, force: true }));
  sh(dir, "git", ["init", "-q", "."]);
  sh(dir, "git", ["config", "user.email", "t@t"]);
  sh(dir, "git", ["config", "user.name", "t"]);
  writeFileSync(join(dir, "CONTEXT.md"), GLOSSARY);
  writeFileSync(join(dir, "base.ts"), "export const ok = 1;\n");
  sh(dir, "git", ["add", "-A"]);
  sh(dir, "git", ["commit", "-qm", "base"]);
  return dir;
}

function commit(dir, msg = "change") {
  sh(dir, "git", ["add", "-A"]);
  sh(dir, "git", ["commit", "-qm", msg]);
}

/** Roda o gate; devolve { status, out }. */
function gate(dir, args = ["--base", "HEAD~1"], env = {}) {
  const r = spawnSync(process.execPath, [GATE, ...args], {
    cwd: dir,
    encoding: "utf8",
    env: { ...process.env, ...env },
  });
  return { status: r.status, out: (r.stdout || "") + (r.stderr || "") };
}

// ── incidentes viram regressão ──────────────────────────────────────────────

test("o gate é texto para o git (regressão do sentinela NUL)", () => {
  const bytes = readFileSync(GATE);
  assert.equal(bytes.indexOf(0), -1, "glossary-gate.mjs contém byte NUL — o git vai tratá-lo como binário");
  for (const b of bytes) {
    const isCtl = b < 9 || (b > 13 && b < 32) || b === 127;
    assert.ok(!isCtl, `byte de controle 0x${b.toString(16)} no arquivo — vira binário para o git`);
  }
});

test("normalização de acento: 'avaliacao' sem acento bate no termo com acento", (t) => {
  const dir = makeRepo(t);
  writeFileSync(join(dir, "a.ts"), "const avaliacaoMedia = 1;\n");
  commit(dir);
  const r = gate(dir);
  assert.equal(r.status, 1);
  assert.match(r.out, /avaliacaoMedia/);
  assert.match(r.out, /Review/);
});

test("JSDoc não é código: continuação de bloco não dispara o gate", (t) => {
  const dir = makeRepo(t);
  writeFileSync(
    join(dir, "a.ts"),
    "/**\n * Parte do fluxo de entrega da loja.\n * Loja aqui é prosa.\n */\nexport const ok2 = 1;\n",
  );
  commit(dir);
  const r = gate(dir);
  assert.equal(r.status, 0, r.out);
});

// ── contrato básico ─────────────────────────────────────────────────────────

test("identificador com termo evitado é acusado, com o canônico na mensagem", (t) => {
  const dir = makeRepo(t);
  writeFileSync(join(dir, "a.ts"), "const storeName = 'x';\n");
  commit(dir);
  const r = gate(dir);
  assert.equal(r.status, 1);
  assert.match(r.out, /storeName/);
  assert.match(r.out, /Merchant/);
});

test("string e comentário de linha não disparam", (t) => {
  const dir = makeRepo(t);
  writeFileSync(join(dir, "a.ts"), 'const label = "Loja do José"; // loja aqui é UI\n');
  commit(dir);
  const r = gate(dir, ["--base", "HEAD~1"]);
  assert.equal(r.status, 0, r.out);
});

test("linha existente não é violação — só o diff conta", (t) => {
  const dir = makeRepo(t);
  writeFileSync(join(dir, "legacy.ts"), "const storeId = 1;\n");
  commit(dir, "legado entra na base");
  writeFileSync(join(dir, "novo.ts"), "export const clean = 1;\n");
  commit(dir, "novo arquivo limpo");
  const r = gate(dir); // HEAD~1 → só novo.ts está no diff
  assert.equal(r.status, 0, r.out);
});

test("plural simples bate no termo (stores → store)", (t) => {
  const dir = makeRepo(t);
  writeFileSync(join(dir, "a.ts"), "const stores = [];\n");
  commit(dir);
  const r = gate(dir);
  assert.equal(r.status, 1);
  assert.match(r.out, /Merchant/);
});

test("identificador composto é quebrado em palavras (listStoreIds)", (t) => {
  const dir = makeRepo(t);
  writeFileSync(join(dir, "a.ts"), "function listStoreIds() {}\n");
  commit(dir);
  const r = gate(dir);
  assert.equal(r.status, 1);
});

// ── modos e configuração ────────────────────────────────────────────────────

test("--staged vê o índice antes do commit", (t) => {
  const dir = makeRepo(t);
  writeFileSync(join(dir, "a.ts"), "const lojaAtual = 1;\n");
  sh(dir, "git", ["add", "a.ts"]); // staged, sem commit
  const r = gate(dir, ["--staged"]);
  assert.equal(r.status, 1);
  assert.match(r.out, /lojaAtual/);
});

test(".glossaryignore isenta por glob, e só o que casa", (t) => {
  const dir = makeRepo(t);
  mkdirSync(join(dir, "lib", "state"), { recursive: true });
  writeFileSync(join(dir, "lib", "state", "a.ts"), "const storeApi = 1;\n");
  writeFileSync(join(dir, "b.ts"), "const storeId = 1;\n");
  writeFileSync(join(dir, ".glossaryignore"), "# zustand\nlib/state/**\n");
  commit(dir);
  const r = gate(dir);
  assert.equal(r.status, 1);
  assert.doesNotMatch(r.out, /lib\/state/);
  assert.match(r.out, /b\.ts/);
});

test("escape declarado: CANUTO_ALLOW_GLOSSARY=1 sai 0 e imprime o motivo", (t) => {
  const dir = makeRepo(t);
  writeFileSync(join(dir, "a.ts"), "const storeId = 1;\n");
  commit(dir);
  const r = gate(dir, ["--base", "HEAD~1"], {
    CANUTO_ALLOW_GLOSSARY: "1",
    CANUTO_ALLOW_REASON: "teste de regressão",
  });
  assert.equal(r.status, 0);
  assert.match(r.out, /OVERRIDE/);
  assert.match(r.out, /teste de regressão/);
});

test("sem CONTEXT.md é erro de configuração (exit 2), nunca aprovação silenciosa", (t) => {
  const dir = makeRepo(t);
  rmSync(join(dir, "CONTEXT.md"));
  writeFileSync(join(dir, "a.ts"), "const storeId = 1;\n");
  commit(dir);
  const r = gate(dir);
  assert.equal(r.status, 2);
});

test("glossário sem _Evitar_ é erro de configuração (exit 2)", (t) => {
  const dir = makeRepo(t);
  writeFileSync(join(dir, "CONTEXT.md"), "# Vazio\n\n**Termo**:\nDefinição sem evitar.\n");
  writeFileSync(join(dir, "a.ts"), "const x = 1;\n");
  commit(dir);
  const r = gate(dir);
  assert.equal(r.status, 2);
});

test("--all varre a árvore inteira, inclusive o legado", (t) => {
  const dir = makeRepo(t);
  writeFileSync(join(dir, "legacy.ts"), "const storeId = 1;\n");
  commit(dir, "legado");
  const r = gate(dir, ["--all", "--json"]);
  assert.equal(r.status, 1);
  const parsed = JSON.parse(r.out.slice(r.out.indexOf("{")));
  assert.ok(parsed.violations.some((v) => v.file === "legacy.ts"));
});

test("arquivo que não é código (md, json) não dispara", (t) => {
  const dir = makeRepo(t);
  writeFileSync(join(dir, "notas.md"), "A loja e a entrega estão em avaliação.\n");
  writeFileSync(join(dir, "dados.json"), '{"store": 1}\n');
  commit(dir);
  const r = gate(dir);
  assert.equal(r.status, 0, r.out);
});
