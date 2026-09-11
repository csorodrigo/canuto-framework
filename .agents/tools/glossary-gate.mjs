#!/usr/bin/env node
/**
 * glossary-gate — falha quando código NOVO introduz termo que o CONTEXT.md
 * marcou como `_Evitar_`.
 *
 * Parte da skill `domain-modeling` do canuto-framework (ADR-0015).
 *
 * DESENHO — por que ele é estreito de propósito (ADR-0012):
 *
 *   Um gate que dispara em coisa legítima vira ruído, e ruído vira override.
 *   A auditoria de 2026-08-01 mediu 92 overrides no mecesa e 246 no lucrando-ai
 *   por exatamente isso. Então este gate abre mão de recall para não ter falso
 *   positivo:
 *
 *   1. Só olha LINHAS ADICIONADAS no diff. O código existente não é violação —
 *      é dívida conhecida, e falhar sobre ela tornaria o gate inútil no dia 1
 *      (o lucrando-ai tem 23.089 ocorrências de `store`).
 *   2. Só olha IDENTIFICADORES. String, comentário e texto de JSX ficam de fora,
 *      porque o glossário registra o português como tradução de UI — `"Loja"`
 *      num label é correto, `storeName` numa variável não é.
 *   3. Respeita `.glossaryignore` (globs), para casos em que o termo tem outro
 *      sentido legítimo — `store` como state container do zustand.
 *
 *   O que ele NÃO pega, e é consciente: termo evitado dentro de string, de
 *   comentário, de nome de arquivo, ou introduzido por código gerado.
 *
 * USO:
 *   node glossary-gate.mjs [--base <ref>] [--staged] [--context <path>] [--all] [--json]
 *
 *   --base <ref>  diff contra a base (pre-push / CI). Default: origin/main.
 *   --staged      diff do índice (pre-commit).
 *   --all         árvore inteira (auditoria da dívida; nunca em gate).
 *
 * SAÍDA:
 *   exit 0  — sem violação (ou escape declarado)
 *   exit 1  — violação encontrada
 *   exit 2  — erro de uso/configuração (CONTEXT.md ausente, base inválida)
 *
 * ESCAPE:
 *   CANUTO_ALLOW_GLOSSARY=1 com CANUTO_ALLOW_REASON="<motivo>".
 *   O escape é para declarar, não para esconder: ele sai no stdout e vira
 *   evento no event log quando `.agents/tools/event-log.sh` existir.
 */

import { execFileSync } from "node:child_process";
import { existsSync, readFileSync } from "node:fs";
import { resolve } from "node:path";

const args = process.argv.slice(2);
const flag = (name, fallback = null) => {
  const i = args.indexOf(`--${name}`);
  return i === -1 ? fallback : (args[i + 1] ?? true);
};
const has = (name) => args.includes(`--${name}`);

const CONTEXT_PATH = resolve(flag("context", "CONTEXT.md"));
const BASE = flag("base", process.env.GLOSSARY_BASE || "origin/main");
const SCAN_ALL = has("all");
const STAGED = has("staged");
const AS_JSON = has("json");

const EXT = /\.(ts|tsx|js|jsx|mjs|cjs)$/;

// ── normalização ────────────────────────────────────────────────────────────
// "avaliação" e "avaliacao" são a mesma palavra para efeito de gate.
const norm = (s) =>
  s
    .normalize("NFD")
    .replace(/[\u0300-\u036f]/g, "")
    .toLowerCase();

// ── 1. parse do CONTEXT.md ──────────────────────────────────────────────────
// Formato (skill domain-modeling, CONTEXT-FORMAT.md):
//
//   **Merchant**:
//   A loja individual cadastrada na plataforma...
//   _Evitar_: store, loja (só como tradução de UI), unidade, filial
//
function parseGlossary(path) {
  if (!existsSync(path)) {
    fail(2, `CONTEXT.md não encontrado em ${path}. Rode /domain-modeling primeiro.`);
  }
  const lines = readFileSync(path, "utf8").split("\n");
  const avoided = new Map(); // termo normalizado -> { canonical, raw }
  let canonical = null;

  for (const line of lines) {
    const term = line.match(/^\*\*(.+?)\*\*\s*:/);
    if (term) {
      canonical = term[1].trim();
      continue;
    }
    const avoid = line.match(/^_Evitar_\s*:\s*(.+)$/i);
    if (!avoid || !canonical) continue;

    for (const piece of avoid[1].split(",")) {
      // "loja (só como tradução de UI)" -> "loja"; a ressalva não muda a regra,
      // porque o gate já ignora string e comentário.
      const raw = piece.replace(/\(.*?\)/g, "").trim();
      if (!raw) continue;
      // Termos de mais de uma palavra não são checáveis como identificador.
      if (/\s/.test(raw)) continue;
      const key = norm(raw);
      if (key.length < 3) continue; // evita ruído de siglas curtas
      if (!avoided.has(key)) avoided.set(key, { canonical, raw });
    }
  }
  if (avoided.size === 0) {
    fail(2, `Nenhum termo \`_Evitar_\` encontrado em ${path}. O gate não tem o que checar.`);
  }
  return avoided;
}

// ── 2. o que checar ─────────────────────────────────────────────────────────
function git(...a) {
  return execFileSync("git", a, { encoding: "utf8", maxBuffer: 64 * 1024 * 1024 });
}

/** Linhas adicionadas no diff: [{ file, line, text }] */
function addedLines(base) {
  const common = ["--unified=0", "--no-color", "--diff-filter=AM"];
  let diff;
  if (STAGED) {
    // pre-commit: o que está no índice, ainda não commitado.
    diff = git("diff", "--cached", ...common);
  } else {
    let range;
    try {
      range = `${git("merge-base", base, "HEAD").trim()}..HEAD`;
    } catch {
      fail(2, `Não consegui resolver a base "${base}". Passe --base <ref> ou defina GLOSSARY_BASE.`);
    }
    diff = git("diff", ...common, range);
  }
  const out = [];
  let file = null;
  let lineNo = 0;
  for (const raw of diff.split("\n")) {
    if (raw.startsWith("+++ b/")) {
      file = raw.slice(6);
      continue;
    }
    const hunk = raw.match(/^@@ -\d+(?:,\d+)? \+(\d+)/);
    if (hunk) {
      lineNo = Number(hunk[1]);
      continue;
    }
    if (raw.startsWith("+") && !raw.startsWith("+++")) {
      if (file && EXT.test(file)) out.push({ file, line: lineNo, text: raw.slice(1) });
      lineNo++;
    }
  }
  return out;
}

/** Modo --all: varre a árvore inteira. Só para auditoria, nunca em CI. */
function allLines() {
  const files = git("ls-files").split("\n").filter((f) => EXT.test(f));
  const out = [];
  for (const file of files) {
    if (!existsSync(file)) continue;
    const src = readFileSync(file, "utf8").split("\n");
    src.forEach((text, i) => out.push({ file, line: i + 1, text }));
  }
  return out;
}

// ── 3. ignore ───────────────────────────────────────────────────────────────
function loadIgnore() {
  const path = ".glossaryignore";
  if (!existsSync(path)) return [];
  return readFileSync(path, "utf8")
    .split("\n")
    .map((l) => l.replace(/#.*$/, "").trim())
    .filter(Boolean)
    .map((glob) => {
      // Passe único, de propósito: a versão em cadeia precisava de um sentinela
      // para segurar `**` entre os replaces, e o sentinela virou byte NUL —
      // o que torna ESTE arquivo binário para o git. Arquivo binário não é
      // revisável em diff e é invisível para o próprio gate, que só lê linhas
      // de texto. Um gate que não consegue se auto-inspecionar é o começo do
      // mesmo problema que ele existe para evitar.
      const rx = glob
        .replace(/[.+^${}()|[\]\\]/g, "\\$&")
        .replace(/\*\*|\*|\?/g, (m) => (m === "**" ? ".*" : m === "*" ? "[^/]*" : "."));
      return new RegExp(`^${rx}$`);
    });
}

// ── 4. só identificadores ───────────────────────────────────────────────────
/** Remove string, template e comentário — o que sobra é código. */
function stripLiterals(text) {
  // Continuação de bloco de comentário. O gate lê o diff LINHA A LINHA, então
  // ele nunca vê o `/*` de abertura de um JSDoc de várias linhas — sem esta
  // regra, cada linha ` * texto` entra como código. Foi o que produziu o
  // primeiro falso positivo real: "Parte da skill..." num cabeçalho JSDoc
  // acusado como o termo de domínio `parte` (Party). JSDoc é onipresente, e
  // falso positivo é o que ensina o time a passar --no-verify.
  const t = text.trim();
  if (t.startsWith("*") || t.startsWith("/*") || t.startsWith("//")) return " ";
  return text
    .replace(/\/\/.*$/g, " ")
    .replace(/\/\*[\s\S]*?\*\//g, " ")
    .replace(/"(?:[^"\\]|\\.)*"/g, ' "" ')
    .replace(/'(?:[^'\\]|\\.)*'/g, " '' ")
    .replace(/`(?:[^`\\]|\\.)*`/g, " `` ");
}

/** "storeSubsidyNet" -> ["store","subsidy","net"]; "client_brands" -> ["client","brands"] */
function words(identifier) {
  return identifier
    .replace(/([a-z0-9])([A-Z])/g, "$1 $2")
    .replace(/([A-Z]+)([A-Z][a-z])/g, "$1 $2")
    .split(/[^A-Za-z0-9]+/)
    .filter(Boolean)
    .map(norm);
}

function scan(entries, avoided, ignores) {
  const violations = [];
  for (const { file, line, text } of entries) {
    if (ignores.some((rx) => rx.test(file))) continue;
    const code = stripLiterals(text);
    const seen = new Set();
    for (const ident of code.match(/[A-Za-z_$][A-Za-z0-9_$]*/g) || []) {
      for (const w of words(ident)) {
        // Plural simples: "stores" bate em "store".
        const key = avoided.has(w) ? w : avoided.has(w.replace(/s$/, "")) ? w.replace(/s$/, "") : null;
        if (!key || seen.has(key)) continue;
        seen.add(key);
        const { canonical, raw } = avoided.get(key);
        violations.push({ file, line, found: ident, term: raw, canonical, text: text.trim() });
      }
    }
  }
  return violations;
}

// ── saída ───────────────────────────────────────────────────────────────────
function fail(code, msg) {
  process.stderr.write(`glossary-gate: ${msg}\n`);
  process.exit(code);
}

function logEvent(kind, detail) {
  const sh = ".agents/tools/event-log.sh";
  if (!existsSync(sh)) return;
  try {
    execFileSync("bash", [sh, "append", "GATE", `glossary-${kind}`, detail], { stdio: "ignore" });
  } catch {
    /* event log é observabilidade, nunca bloqueia o gate */
  }
}

const avoided = parseGlossary(CONTEXT_PATH);
const entries = SCAN_ALL ? allLines() : addedLines(BASE);
const violations = scan(entries, avoided, loadIgnore());

if (AS_JSON) {
  process.stdout.write(JSON.stringify({ violations, checked: entries.length }, null, 2) + "\n");
}

if (violations.length === 0) {
  if (!AS_JSON) {
    process.stdout.write(
      `glossary-gate: OK — ${entries.length} linha(s) nova(s), ${avoided.size} termo(s) vigiado(s), 0 violação.\n`,
    );
  }
  process.exit(0);
}

if (!AS_JSON) {
  process.stdout.write(`\nglossary-gate: ${violations.length} violação(ões) em código novo.\n\n`);
  for (const v of violations) {
    process.stdout.write(`  ${v.file}:${v.line}\n`);
    process.stdout.write(`    ${v.found}  —  "${v.term}" está em _Evitar_; o termo canônico é "${v.canonical}"\n`);
    process.stdout.write(`    ${v.text}\n\n`);
  }
  process.stdout.write(
    `O glossário está em ${CONTEXT_PATH}. Se o termo estiver certo e o glossário errado,\n` +
      `corrija o glossário (skill /domain-modeling) — não contorne o gate.\n` +
      `Se o arquivo usa o termo em outro sentido legítimo, adicione-o ao .glossaryignore.\n` +
      `Escape declarado: CANUTO_ALLOW_GLOSSARY=1 CANUTO_ALLOW_REASON="<motivo>"\n\n`,
  );
}

if (process.env.CANUTO_ALLOW_GLOSSARY === "1") {
  const reason = process.env.CANUTO_ALLOW_REASON || "(sem motivo declarado)";
  process.stdout.write(`glossary-gate: OVERRIDE — ${violations.length} violação(ões) ignorada(s). Motivo: ${reason}\n`);
  logEvent("override", `${violations.length} violações; motivo: ${reason}`);
  process.exit(0);
}

logEvent("block", `${violations.length} violações`);
process.exit(1);
