# Project Rules (Codex)

## Context
- Framework: Canuto v1.x at .agents/
- Read .context.md files in each directory for local context
- Read docs/FEATURE-MAP.md for feature status and flows
- Read .agents/tmp/context-package.md if it exists (pre-loaded context from Architect)

## Coding Rules
- Prefer the simplest implementation that fully meets the current requirement. No speculative abstraction, configuration, or indirection.
- Grow in layers: smallest version that works end to end first, each new capability on top of something that already works. Never leave the tree broken mid-refactor.
- Do not assume a library lacks a capability without checking its docs and types.
- Follow existing patterns in nearby files — match style, naming, structure
- Do NOT add new dependencies without explicit instruction in the prompt
- Include basic happy-path tests for new functions
- Use TypeScript strict mode if tsconfig.json has strict: true
- Prefer editing existing files over creating new ones
- Do NOT add comments, docstrings, or type annotations to code you didn't change

## Design Rules (mandatory for any UI work)
- Before planning, implementing, or reviewing ANY user-facing UI, read
  `.agents/design/DESIGN-RULES.md` and obey it. It is the normative design
  system: density, type scale, spacing ceilings, overflow bans, copy rules.
- On conflict with any other guidance, DESIGN-RULES.md wins.

## MCP Tools Available
- **obsidian-vault**: Read/write vault notes at ~/.canuto/vault/ for project memory
- **ast-grep**: Structural code search — use for finding patterns, symbols, callers
- **playwright**: Browser automation — navigate, click, fill, screenshot, assert
- **claude-architect**: Delega planejamento/arquitetura a Claude — `mcp__claude-architect__spawn_agent`
- **claude-reviewer**: Review cross-model via Claude — `mcp__claude-reviewer__spawn_agent`
  - Modelo por alias (`fable`/`opus`), definido em `.agents/tools/claude-agent-mcp.py`
    (`MODE_DEFAULTS`), com `--fallback-model` automático. Não pinar versão.
  - Use for bias-free review: Codex implements → Claude reviews (or vice-versa)
  - Same interface as `codex-reviewer`: pass diff between `--- CHANGES START/END ---` delimiters

## Vault Access (Fallback)
If MCP tools are not available, use the vault-bridge shell script:
```bash
bash .agents/tools/vault-bridge.sh read <note-path>
bash .agents/tools/vault-bridge.sh search <query>
```

## File Conventions
- New files follow the naming pattern of existing files in the same directory
- Imports use the project's alias paths (check tsconfig.json or package.json)
- Test files go next to source files or in the nearest tests/ directory

## Codex Roles

**Modelo e effort NÃO são declarados aqui.** Fonte única: `.agents/config/models.yaml`
— é o arquivo que o wrapper realmente lê. Duplicar versão em doc é como a
defasagem começa (esta tabela dizia `gpt-5.5` até 2026-07-26, enquanto o real
já era gpt-5.6).

| Role | Use For |
|------|---------|
| `coder` | Geração de código, refactor, edits multi-arquivo |
| `reviewer` | Review de código e plano (roda read-only) |
| `architect` | Arquitetura, decomposição complexa |
| `maestro` | Orquestração em runtime Codex direto |
| `fast` | Edits rápidos, formatação, docs (tier mais barato) |

Caminho canônico:

```bash
~/.codex/bin/codex-delegate.sh <role> <task-file> <out-file>
```

- **`--profile` não é lido pelo wrapper.** Vale para `codex exec` cru e para o
  app Desktop, via `~/.codex/<role>.config.toml` (perfis v2) — **não** pelos
  blocos `[profiles.*]` de `config.toml`, que o codex-cli 0.135+ ignora.
  Exceção viva: `codex-pretool-guard.sh` usa `--profile fast` no tier degradado
  do review de pre-commit.
- **Nunca use `-q`** (removido no codex-cli 0.135 — causava falha instantânea).
- Nunca `codex exec` cru para trabalho de coder: omite `-s` e herda
  `sandbox_mode="danger-full-access"` + `approval_policy="never"`.
- Sessões Claude mantêm Claude como Maestro (alias `fable`, fallback `opus`).
- Sessões Codex diretas: `bash .agents/tools/codex-maestro.sh`.

## Contrato de Eventos e Gates (sessões Codex diretas)

Os hooks PreToolUse/Stop são do **Claude Code** e não disparam em sessão Codex
direta — por isso o contrato foi movido para costuras que valem em QUALQUER
runtime (validado end-to-end em 2026-07-27, 15/15 checks):

**Mecânico (não depende de você):**
- **git pre-push gate** (`.agents/hooks/git-pre-push-gate.sh`, instalado como
  `.git/hooks/pre-push`): primeiro push de branch roda
  `require-tests-for-pr.sh` — teste falhando bloqueia o push; push direto
  para main é bloqueado. Escapes conscientes ficam no event log:
  `CANUTO_SKIP_PR_GATE=1` (testes) e `CANUTO_ALLOW_MAIN_PUSH=1` (main).
  Os escapes são independentes: liberar a main NÃO pula o gate de testes.
- **codex-maestro.sh** registra SESSION_START/SESSION_END sozinho e, na
  saída, cobra CLOSEOUT do dia (mesmo gate do session-save.sh do lado
  Claude). Sempre entre por ele — nunca `codex` cru no projeto.

**Disciplina (ainda é seu papel):**
- **Ao encerrar a sessão**: rode o fluxo de session-end-learning e registre
  `bash .agents/tools/event-log.sh append CLOSEOUT actor=codex-maestro summary="<3-8 palavras>"`.
  O wrapper avisa na saída se o dia fechou sem CLOSEOUT.
- **Eventos significativos** (delegação interna, gate, decisão): registre com
  `event-log.sh append` — o log é a fonte de verdade compartilhada entre os
  dois runtimes; notas são projeções.
- **Memória**: tier hipótese (session notes, metrics, instinct candidates com
  `confidence: low`) grava direto e anuncia; tier curado (promoções de
  instinct, decisions, regras) exige aprovação humana explícita.

## Anti-Patterns
- Do NOT create README.md, documentation files, or CHANGELOG entries
- Do NOT refactor unrelated code
- Do NOT install packages or modify lock files
- Do NOT modify .env files or configuration
