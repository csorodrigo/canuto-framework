---
type: pending
id: P-005
status: pending
priority: medium
owner: ""
provider: ""
created-session: "2026-04-18"
source: "Repomix/aider/claude-code-memory-setup research"
inspired-by: "Aider repo-map (PageRank-style ranking) + Graphify pattern from lucasrosati/claude-code-memory-setup"
license-note: "patterns are MIT-licensed; clean-room implementation if any code adapted"
rework-count: 0
retry-count: 0
tags:
  - pending
  - tooling-idea
  - vault
  - codebase-graph
  - ast
---

# Codebase AST graph no vault (Graphify-style)

**Pattern:** Gerar `.agents/vault/codebase/graph.json` via AST parsing (Tree-sitter ou ast-grep que já temos) com nodes (arquivos, classes, funções) e edges (imports, calls, type-references). Skill `/codebase-graph` query nesse JSON ao invés de re-ler arquivos.

**Por que vale:**
- Vault hoje tem decisions/sessions/instincts mas **nada sobre estrutura do código**
- Quando Maestro/Coder precisa "qual função chama X", a única opção atual é grep + leitura
- Aider documentou ganhos significativos com PageRank no graph (rank de centralidade dos arquivos para escolher o que entra no contexto)
- claude-code-memory-setup (lucasrosati, PT-BR) reporta "querying graph.json = 280 tokens vs reading 40 files = 20k tokens"

**Diferença vs Repomix MCP (já adicionado):**
- Repomix produz **dump compacto on-demand** do código todo
- Graphify produz **knowledge graph persistente** com relações navegáveis
- Complementares, não substitutos: Repomix pra carga inicial, Graphify pra queries dirigidas

**Arquitetura proposta:**
```
.agents/vault/codebase/
  graph.json              # nodes + edges (gerado)
  graph-meta.yaml         # last-updated, file-count, language
  rank.json               # PageRank score por node (cache)
.agents/tools/
  generate-codebase-graph.sh    # roda ast-grep + monta JSON
  query-graph.sh                # CLI pra queries comuns (callers, callees)
.agents/hooks/
  refresh-graph-on-commit.sh    # atualiza após commits que mudam .ts/.py/.rs
```

**Skill nova: `/codebase-graph`**
- `--callers <symbol>` — quem chama
- `--callees <symbol>` — quem é chamado
- `--depends-on <file>` — dependências
- `--top-rank N` — top N arquivos por PageRank

**Estimativa:** L. Tem partes:
1. Parser AST (Tree-sitter via ast-grep MCP que já temos) — M
2. Graph builder + JSON schema — M
3. PageRank scorer — S
4. Skill markdown + CLI helpers — S
5. Hook de refresh + integração com session-start — S

**Bloqueadores / decisões:**
- Linguagens cobertas no V1? (sugestão: TS/JS + Python, expansão depois)
- Tamanho máximo razoável do graph.json antes de paginar/sharding?
- Como invalidar cache em refactors grandes (mudança de naming)?

**Source:** sessão 2026-04-18, research turn sobre input compression. Originado da resposta sobre Repomix vs Headroom vs claude-code-memory-setup.
