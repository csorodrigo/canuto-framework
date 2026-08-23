# ADR-0003 — O genótipo é cego a identidade; um grep-gate impõe isso

Data: 2026-07-26 · Status: aceito

## Contexto

Dois vazamentos de identidade no código distribuível: (1) o `merge_claude_md`
baixava o CLAUDE.md do próprio repo canuto para projetos novos — com
`project-slug: canuto-framework-v1` dentro — colidindo a memória de todos os
installs novos no mesmo slug (follow-up #1 da auditoria 2026-04-17, aberto
por 3 meses); (2) o pipeline `framework-session-audit` tinha como default o
path absoluto do workspace de um desenvolvedor específico.

O edge-of-chaos trata isso como classe de bug com teste próprio
(`test_identity_blinding.py`): literais de install banidos do genótipo, com
grep no repo falhando o build.

## Opções consideradas

1. **Corrigir os dois casos e seguir** — rejeitada: o slug já tinha sido
   "corrigido" por projeto antes e regrediu; sem guarda, volta.
2. **Grep-gate no test-framework** — aceita: regressão vira falha de suite.

## Decisão

- `merge_claude_md` gera template limpo (sem slug — `canuto-memory.sh` cai
  no basename do diretório); nunca baixa o CLAUDE.md do repo canuto.
- `framework-session-audit`: workspaces root = `CANUTO_WORKSPACES_ROOT` >
  `~/conductor/workspaces` se existir > desabilitado. Nenhum path de
  desenvolvedor no código.
- Test 11 do `test-framework.sh` (grep-gate): literais banidos em
  install.sh/hooks/tools/templates; install.sh proibido de semear o slug do
  canuto; `merge_claude_md` proibido de voltar ao download; e sync
  bidirecional FRAMEWORK_FILES ↔ `.agents/skills/` (o drift dos 30 arquivos
  nunca distribuídos também era um bug de "genótipo ≠ o que se declara").

- Defaults instaláveis e configurações bootstrap são identidade-cegas: projetos, hosts e paths reais vivem somente em `~/.canuto/config/`.

## Consequências

- (+) As duas regressões conhecidas ficam estruturalmente impossíveis de
  passar despercebidas.
- (−) A lista de literais banidos é enumerada, não geral — nomes novos
  precisam ser adicionados quando aparecerem (mesmo trade-off do edge).
