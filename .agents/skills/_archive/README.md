# Skills Aposentadas

Skills movidas para cá em **2026-06-11** — 0 leituras em runtime na auditoria de 200 sessões
(apenas 3 dos ~85 skills raiz foram lidos alguma vez) e nenhuma referência ativa em
CLAUDE.md, personas, hooks, SPEC, TUTORIAL, plugins, mcp, tools ou install.sh.

Para restaurar uma skill: `git mv .agents/skills/_archive/<nome>.md .agents/skills/<nome>.md`
(e re-adicionar a entrada correspondente em `FRAMEWORK_FILES` no `install.sh`, se aplicável).

## 2026-07-26 — segunda leva (grafo de invocação)

Arquivados por **zero caminho real de invocação** (mapeamento com subagentes,
2026-07-26 — nenhuma persona, hook, CLAUDE.md ou skill de entrada os citava;
critério idêntico ao da poda de 2026-06-11):

`obsidian-cli`, `squads`, `session-reset/` (o trigger `/session-reset` nunca
era instalado pelo install.sh), `json-canvas` (+ `json-canvas-references/`),
`obsidian-bases` (+ `obsidian-bases-references/`), `cli-usage`, `git-workflow`,
`stack-lock`, `plugin-system` (o mecanismo de descoberta de plugins descrito
no skill nunca foi implementado em Maestro/hooks/CLAUDE.md).

Nota: os arquivos `.base` e `.canvas` do vault continuam funcionando no app
Obsidian — os skills arquivados eram documentação de formato para o agente,
não o mecanismo de escrita.
