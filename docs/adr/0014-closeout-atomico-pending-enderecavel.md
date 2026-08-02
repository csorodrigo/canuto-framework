# ADR-0014 — Closeout atômico: publicar é registrar; pending nunca evapora por omissão

Data: 2026-08-01 · Status: aceito

## Contexto

O gate de `CLOSEOUT_TODAY` já existente em `session-save.sh` prova que
**algo** foi salvo no fim da sessão — não que o conteúdo é utilizável. Uma
nota de sessão sem next-entrypoint acionável, sem admissão de retrabalho
registrada, sem pending correspondente, é memória write-only: fica no vault,
mas ninguém nunca mais age sobre ela. O edge-of-chaos nomeia os dois defeitos
que essa lacuna combina: publicar e registrar memória como **atos separados**
(ADR-0012 dele: `artefatos_without_kernel()` deve bloquear) e itens de
pending/direction que **evaporam por omissão** — o closeout de uma sessão
esquece de repetir um item pendente e ele desaparece (ADR-0007 dele).

## Opções consideradas

1. **Manter o closeout como só o gate de evento** (`CLOSEOUT_TODAY`), sem
   exigir nada do conteúdo da nota — rejeitada: prova gravação, não prova
   memória utilizável; é a lacuna medida.
2. **Destilar pending/rework só quando o closeout está "completo"** (com
   kernel) — rejeitada deliberadamente: um fechamento capenga, sem kernel, é
   exatamente o caso onde a rede de segurança de Next-Entrypoint/rework/
   segredo mais importa. Restringir a destilação à publicação completa
   derrotaria o propósito anti-evaporação.
3. **Destilação mecânica roda sempre que existe nota canônica** (kernel
   presente ou não); nota sem kernel gera aviso explícito mas passa pela
   mesma destilação — aceita.

## Decisão

- `session-save.sh` (`:177-433`): o closeout conta como **PUBLICADO** só
  quando a nota canônica da sessão contém o kernel de 3 linhas
  (`intent:`/`porque:`/`proximo:`) ou o contrato legado
  `Summary`/`Proof`/`Next Entrypoint` já usado por `canuto-brain closeout`
  (formato antigo não é penalizado). `CLOSEOUT_PUBLISHED` (`:373-380`) é
  emitido via `canuto_event_append` **no mesmo ato** que grava a nota, com
  `{status, kernel_intent/porque/proximo, pendings_created,
  reworks_created, secret_alert}`. Nota sem kernel não bloqueia — reporta
  "closeout sem intent kernel — memória write-only" e
  `status=incomplete reason=no_kernel`.
- `_a5_create_pending` (`:211`): Next-Entrypoint acionável sem pending
  correspondente → cria `<vault>/pending/<data>-<id>.md`, `status: proposed`.
- `_a5_create_rework` (`:241`): admissão de retrabalho ("redescobri", "de
  novo", "já estava na memória", "refiz") → nota em `<vault>/rework/`
  (diretório **novo**), mesmo formato.
- `_a5_secret_evidence` / `_a5_secret_names` (`:274`/`:278`): menção a
  segredo/rotação vira alerta impresso **no topo** da saída do hook — só
  nomes de variável extraídos (tudo após `=` é cortado antes do extrator),
  nunca o valor.
- Anti-duplicata: nota canônica da mesma sessão (janela de minutos) atualiza
  em vez de criar segunda — rodar o hook 2× sobre a mesma nota produz 1
  arquivo em `pending/` e 1 em `rework/`, testado.
- Pendings/rework endereçáveis (`canuto-pending-triage.md`, seção
  "Addressable Convention"): frontmatter `id` / `status: proposed | set |
  dropped` / `created` / `dropped-reason` (obrigatório quando dropped). Um
  item **nunca é deletado** — dropar é `status: dropped` + razão, o arquivo
  fica. Entradas `proposed` nascem permissivas; o funil de curadoria se
  aplica à promoção (`proposed` → `set`), não à entrada (eoc ADR-0007: a
  barreira é na saída, não na porta).

## Consequências

- (+) Um closeout sem intent kernel deixa de ser silêncio: aparece como
  aviso explícito e evento `status=incomplete`.
- (+) Next-entrypoint, admissão de retrabalho e menção a segredo viram
  artefato endereçável ou alerta visível automaticamente, sem depender de o
  agente lembrar de criar a nota — ataca a evaporation-by-omission na
  origem.
- (−) `rework/` é um diretório **novo** no vault, divergente do padrão hoje
  usado por `canuto-brain.mjs rework` (que grava em `pending/` com tag
  `rework`). A spec pediu literalmente "crie nota em rework/", e a
  implementação seguiu à risca em vez de convergir com a ferramenta
  existente (fora da posse desta frente). Os dois caminhos coexistem hoje
  sem reconciliação — reportado, não corrigido; decisão de convergência fica
  para quem tocar `canuto-brain.mjs`.
- (−) Risco residual conhecido e não mitigado: se uma admissão de retrabalho
  e uma menção a segredo caírem na **mesma linha** da nota original,
  `_a5_create_rework` copia a linha de evidência verbatim para o corpo da
  nota de rework — a sanitização de `_a5_secret_names` cobre só o alerta
  impresso no stdout do hook, não essa cópia.
- (−) `CLOSEOUT_STATUS` (este ADR) e `CLOSEOUT_TODAY` (ADR-0002) são sinais
  independentes hoje: `canuto-brain closeout` escreve a nota mas nunca
  chamou `event-log.sh append`, e `canuto-session-end-learning` emite o
  evento mas não escreve a nota kernel. Os dois aparecem lado a lado na
  mesma saída do hook; unificá-los é trabalho futuro.
