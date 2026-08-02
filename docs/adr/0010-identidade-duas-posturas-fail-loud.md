# ADR-0010 — Identidade do projeto resolve num seam só, em duas posturas

Data: 2026-08-01 · Status: aceito

## Contexto

`canuto-memory.sh` já resolvia o slug do projeto por cascata (override no
`CLAUDE.md` → colapso de container de worktree → remote `origin` → basename)
e degradava sozinho quando nada batia — sempre devolvendo *algo*, mesmo que
fosse um basename inventado. Essa leitura silenciosa é a mesma classe de bug
que o edge-of-chaos documenta na ADR-0015 dele: uma resolução degradada sem
rótulo escondeu 294 sessões perdidas ("nothing new" mentiroso), porque nada
diferenciava "projeto genuinamente novo" de "identidade que não resolveu".

O mesmo problema apareceu neste vault durante o teste desta frente: o produto
tem notas espalhadas em dois diretórios — `canuto-framework` (7 notas) e
`canuto-framework-v1` (8 notas) — porque em algum momento o slug resolvido
mudou e ninguém percebeu a fragmentação (achado real, não hipotético).

## Opções consideradas

1. **Manter uma postura única** (sempre degradar, sempre devolver algo) —
   rejeitada: é o comportamento que já causou a fragmentação medida acima.
2. **Bloquear toda resolução sem override explícito do usuário** — rejeitada:
   inutilizaria a leitura em qualquer projeto legítimo sem `project-slug:`
   declarado no `CLAUDE.md`.
3. **Duas posturas por caso de uso** — leitura continua degradando e
   rotulando a degradação; escrita falha alto nomeando o gap — aceita.

## Decisão

- `canuto_require_project_slug <dir>` (`.agents/tools/canuto-memory.sh:470`)
  — a postura de escrita/install. Critério documentado no código: **o slug
  sobreviveria a um `git worktree add`?** Override do `CLAUDE.md`, colapso de
  container e basename do remote `origin` sobrevivem (aceitos); basename do
  toplevel do repo não sobrevive (`git worktree add ../damascus` num repo
  `canuto-framework` viraria o slug `damascus` — identidade nova a cada
  worktree) e é recusado. Falha imprime stdout vazio, `exit 1`, e nomeia em
  stderr cada fonte tentada e por que foi recusada.
- `canuto_classify_vault [slug] [dir]` (`:637`) → `POPULATED` \| `FRESH` \|
  `ORPHAN` (um único token em stdout, detalhe em stderr). `ORPHAN` só dispara
  quando o vault do slug está vazio **e** existe um irmão do mesmo produto
  com notas — emite o evento `VAULT_ORPHAN` via `canuto_event_append`. Irmão
  candidato existente mas vazio classifica `FRESH`, nunca órfão inventado.
- `canuto_fresh_clone_check [dir]` (`:693`) → `OK` \| `TEMPLATE-CLONE` \|
  `UNINITIALIZED` \| `NOT-CANUTO`. É o guard "sou clone do template ou
  install vivo?" do `AGENTS.md` do edge-of-chaos, adaptado: detecta
  `CLAUDE.md` declarando `canuto-framework[-v1]` num repo que não é o
  framework (contaminação real, já vista no repo mecesa).
- Nenhuma das três funções cacheia no momento do `source` — só dentro de
  função, respeitando `CANUTO_SLUG_NO_CACHE=1` (mesmo invariante que o Track
  B já tinha estabelecido para a cascata de slug; comentado explicitamente em
  `canuto-memory.sh:46-55` citando a ADR-0015 do eoc).
- `canuto-project-doctor.md` ganha um `Step 0 — Identity Gate` que roda as
  três funções antes de qualquer outro diagnóstico; `ORPHAN` trava a run em
  `BROKEN` nomeando o irmão. O doutor **nunca conserta sozinho** — diagnostica
  e prescreve (`canuto-init`, corrigir `project-slug:`, ou consolidar vault),
  sempre com aprovação humana.

## Consequências

- (+) A fragmentação real deste vault (`canuto-framework` vs
  `canuto-framework-v1`) agora aparece como aviso de fragmentação em
  `canuto_classify_vault`, em vez de ficar invisível atrás de um `POPULATED`
  silencioso.
- (+) Escrita contaminada entre projetos (o cenário que gerou 294 sessões
  perdidas no eoc) fica estruturalmente impossível: sem slug que sobreviva a
  worktree, não há write.
- (−) `canuto_check_identity`, citado pelo Step 0 do doctor, é implementado
  em `.agents/tools/brief-compose.sh` (frente A4, ver ADR-0011) — dependência
  cruzada entre frentes; se A4 regredir a assinatura, o Step 0 perde uma das
  quatro chamadas sem que A3 perceba.
- (+) Os testes de sandbox que validaram este comportamento (46 asserções,
  ver `.context/fase2/receipts/A3-identity.md`) foram portados para o
  `test-framework.sh` como Test 15 (27 asserções herméticas: require recusa
  basename / aceita override, container e remote; classify nos 3 estados com
  exit codes e evento `VAULT_ORPHAN`; fresh-clone nos 4 estados).
