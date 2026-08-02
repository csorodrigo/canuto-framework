#!/usr/bin/env bash
# brief-compose.sh — compositor do brief do vault + gate de identidade (Fase 2, A4).
#
# Extraído de session-start.sh (Track A, auditoria 2026-08-01), onde nasceu como
# build_vault_brief(). O motivo da extração NÃO é estética: um compositor que só
# existe dentro do hook não pode ser PROVADO. Enquanto ele fosse privado, um
# briefing vazio por quebra era indistinguível de um briefing vazio por não ter
# nada a dizer — a "lobotomia silenciosa" do edge-of-chaos
# (docs/briefing-lifecycle-audit.md). Agora ele é chamável pelo doctor e pelos
# testes, e vem acompanhado do gate que o exercita.
#
# CONTRATO required vs expected-empty (eoc briefing-lifecycle-audit):
#   - REQUIRED: Identity. Seção required vazia é BUG, nunca "está tudo bem".
#     Slug não resolvido imprime MARCADOR DE FALHA, jamais string vazia.
#   - expected-empty tem TRÊS estados, nunca dois:
#       (1) vault existe, seção sem itens   -> marcador honesto de vazio;
#       (2) vault DECLARADO no CLAUDE.md e ausente no disco -> QUEBRADO
#           (feeder declarado-e-ausente: o brief silencioso aqui era a falha
#           de maior alavancagem — a memória parecia vazia, estava desligada);
#       (3) nada declarado e sem vault      -> projeto fresco, 1ª sessão.
#   - eoc ADR-0010: brief é ENTRY POINT, não dump. Caps do Track A preservados
#     (5 pending / 3 instincts / 40 linhas / 3KB).
#
# Ordenação: quando .agents/tools/memory-usage.sh existe e o store tem sinal,
# pending/instincts saem ranqueados por uso (recência+frequência). O rerank
# acontece ANTES de qualquer gravação de uso (invariante eoc N3) — quem grava é
# o session-start.sh, depois de compor.
#
# Uso como biblioteca:
#   source .agents/tools/brief-compose.sh
#   canuto_compose_brief "$GIT_ROOT"
#   canuto_check_identity "$GIT_ROOT"
#
# Uso como CLI:
#   bash brief-compose.sh brief [root]
#   bash brief-compose.sh check-identity [root]   # exit != 0 em FAIL
#
# Nunca falha o chamador (canuto_compose_brief sempre retorna 0). Bash 3.2.

_CANUTO_BRIEF_LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}" 2>/dev/null)" 2>/dev/null && pwd)"
[ -n "$_CANUTO_BRIEF_LIB_DIR" ] || _CANUTO_BRIEF_LIB_DIR="."

# ── Marcadores honestos ─────────────────────────────────────────────────────
# São CONTRATO, não texto solto: `canuto_check_identity` (perna 2) procura
# exatamente estas strings num vault fresco descartável. Mudar o texto sem
# mudar o gate quebra a prova de que o compositor sabe renderizar o vazio.
CANUTO_BRIEF_MARK_IDENTITY_FAIL='⚠ identidade não resolvida — vault não consultado (rode canuto-project-doctor)'
CANUTO_BRIEF_MARK_NO_SESSION='(nenhuma sessão registrada)'
CANUTO_BRIEF_MARK_NO_ENTRY='(nenhum next-entrypoint declarado)'
CANUTO_BRIEF_MARK_NO_PENDING='(nenhum pending registrado)'
CANUTO_BRIEF_MARK_NO_INSTINCT='(nenhum instinct registrado)'
CANUTO_BRIEF_MARK_FRESH='(projeto sem vault — 1ª sessão?)'
CANUTO_BRIEF_MARK_VAULT_ABSENT='⚠ vault declarado'

# ── Telemetria de uso (opcional) ────────────────────────────────────────────
# Cascata: lib do repo → lib global instalada → stubs no-op. O rerank é um
# LUXO: sem ele o brief sai na ordem de mtime, exatamente como antes.
if ! command -v canuto_usage_rerank >/dev/null 2>&1; then
  if [ -f "$_CANUTO_BRIEF_LIB_DIR/memory-usage.sh" ]; then
    . "$_CANUTO_BRIEF_LIB_DIR/memory-usage.sh" 2>/dev/null || true
  elif [ -n "${CLAUDE_PROJECT_DIR:-}" ] && [ -f "$CLAUDE_PROJECT_DIR/.agents/tools/memory-usage.sh" ]; then
    . "$CLAUDE_PROJECT_DIR/.agents/tools/memory-usage.sh" 2>/dev/null || true
  elif [ -f "$HOME/.canuto/lib/memory-usage.sh" ]; then
    . "$HOME/.canuto/lib/memory-usage.sh" 2>/dev/null || true
  fi
fi
if ! command -v canuto_usage_rerank >/dev/null 2>&1; then
  canuto_usage_rerank() { cat 2>/dev/null || true; }
fi
if ! command -v canuto_usage_record >/dev/null 2>&1; then
  canuto_usage_record() { return 0; }
fi

_canuto_brief_markers_ok() {
  # Contrato dos marcadores, checado ANTES de qualquer perna do gate.
  # Um marcador VAZIO não é um detalhe cosmético: a perna 2 procura o marcador
  # com `case "$fresh" in *"$m"*` e `*""*` casa com QUALQUER string — o gate
  # passaria por vacuidade justamente quando o compositor está mudo. Marcador
  # vazio é, ele próprio, a falha (mesmo espírito do fail-closed do eoc
  # check_identity: "não consegui determinar" nunca é passe).
  # Imprime o NOME do marcador quebrado e retorna != 0.
  [ -n "${CANUTO_BRIEF_MARK_IDENTITY_FAIL:-}" ] || { printf 'IDENTITY_FAIL'; return 1; }
  [ -n "${CANUTO_BRIEF_MARK_NO_SESSION:-}" ]    || { printf 'NO_SESSION'; return 1; }
  [ -n "${CANUTO_BRIEF_MARK_NO_ENTRY:-}" ]      || { printf 'NO_ENTRY'; return 1; }
  [ -n "${CANUTO_BRIEF_MARK_NO_PENDING:-}" ]    || { printf 'NO_PENDING'; return 1; }
  [ -n "${CANUTO_BRIEF_MARK_NO_INSTINCT:-}" ]   || { printf 'NO_INSTINCT'; return 1; }
  [ -n "${CANUTO_BRIEF_MARK_FRESH:-}" ]         || { printf 'FRESH'; return 1; }
  [ -n "${CANUTO_BRIEF_MARK_VAULT_ABSENT:-}" ]  || { printf 'VAULT_ABSENT'; return 1; }
  return 0
}

_canuto_brief_status_write() {
  # Canal lateral opcional para o hook: quem exporta CANUTO_BRIEF_STATUS_FILE
  # recebe o balanço estrutural da composição (quais seções vieram cheias,
  # vazias e quebradas) sem precisar reparsear o texto do brief. É isso que
  # alimenta o evento BRIEF_COMPOSED e o canuto_usage_record da sessão.
  # Nenhum valor pode conter \n: slug vem do slugify/override (grep de token
  # sem espaço), paths e refs vêm de linhas de `ls` — por construção, uma linha.
  local f="${CANUTO_BRIEF_STATUS_FILE:-}"
  [ -n "$f" ] || return 0
  {
    printf 'slug=%s\n' "${1:-}"
    printf 'vault=%s\n' "${2:-}"
    printf 'vault_state=%s\n' "${3:-}"
    printf 'sections_populated=%s\n' "${4:-}"
    printf 'sections_empty=%s\n' "${5:-}"
    printf 'sections_broken=%s\n' "${6:-}"
    printf 'refs=%s\n' "${7:-}"
  } > "$f" 2>/dev/null || true
  return 0
}

_canuto_brief_list() {
  # Lista até $3 notas .md de $1 (mais recentes primeiro), reordenadas por uso
  # quando há sinal. $2 = prefixo da ref ("pending"/"instinct"), $4 = slug.
  # Ranqueia 200 candidatos ANTES de cortar: cortar por mtime primeiro tiraria
  # do rerank justamente a nota antiga-e-quente que ele existe para resgatar.
  local dir="${1:-}" prefix="${2:-}" max="${3:-5}" slug="${4:-}"
  local raw="" ranked="" rank=0
  # `|| true` DENTRO da substituição: com pipefail ligado, o SIGPIPE que o
  # `head` provoca no `ls` de um diretório grande derrubaria o rc e um
  # `|| raw=""` externo apagaria uma lista boa.
  raw=$(ls -t "$dir" 2>/dev/null | grep '\.md$' | head -200 || true)
  [ -n "$raw" ] || return 0
  # Store de uso frio (o caso comum) não monta pipeline nenhum: a checagem é um
  # teste de arquivo sem fork, e sem sinal a ordem por mtime já é a resposta.
  if [ -n "$slug" ] && command -v _canuto_usage_store_compute >/dev/null 2>&1; then
    _canuto_usage_store_compute "$slug"
    [ -s "${_CANUTO_USAGE_STORE:-}" ] && rank=1
  fi
  if [ "$rank" = 1 ]; then
    ranked=$(printf '%s\n' "$raw" \
      | sed "s|^|${prefix}:|" \
      | canuto_usage_rerank "$slug" 2>/dev/null \
      | sed "s|^${prefix}:||" || true)
  fi
  # Telemetria nunca pode ESVAZIAR uma seção que tem conteúdo: rerank mudo
  # degrada para a ordem por mtime.
  [ -n "$ranked" ] || ranked="$raw"
  printf '%s\n' "$ranked" | head -"$max" || true
  return 0
}

# canuto_compose_brief <root>
# Imprime o brief. SEMPRE retorna 0 e SEMPRE imprime alguma coisa: a ausência
# de saída é reservada para "não fui chamado".
canuto_compose_brief() {
  local root="${1:-$(pwd)}"
  local slug="" strict_slug="" fragile=0 declared="" vault="" out=""
  local pop="" empty="" broken="" refs="" state=""
  local sess_dir="" latest="" title="" entry="" dir="" n_total="" listed="" f="" t=""
  local prev_opts=""

  # Slug SEMPRE via canuto-memory.sh — a lógica de slug tem dono único (A3).
  # Cascata: lib do repo consumidor → lib ao lado desta → lib global instalada.
  if ! command -v canuto_project_slug >/dev/null 2>&1; then
    prev_opts="$-"
    if [ -f "$root/.agents/tools/canuto-memory.sh" ]; then
      . "$root/.agents/tools/canuto-memory.sh" 2>/dev/null || true
    elif [ -f "$_CANUTO_BRIEF_LIB_DIR/canuto-memory.sh" ]; then
      . "$_CANUTO_BRIEF_LIB_DIR/canuto-memory.sh" 2>/dev/null || true
    elif [ -n "${CLAUDE_PROJECT_DIR:-}" ] && [ -f "$CLAUDE_PROJECT_DIR/.agents/tools/canuto-memory.sh" ]; then
      . "$CLAUDE_PROJECT_DIR/.agents/tools/canuto-memory.sh" 2>/dev/null || true
    elif [ -f "$HOME/.canuto/lib/canuto-memory.sh" ]; then
      . "$HOME/.canuto/lib/canuto-memory.sh" 2>/dev/null || true
    fi
    # canuto-memory.sh liga `set -euo pipefail`; um source não pode mudar as
    # opções do chamador — restaura (mesmo padrão do event-log.sh / Track A).
    case "$prev_opts" in *e*) : ;; *) set +e ;; esac
    case "$prev_opts" in *u*) : ;; *) set +u ;; esac
  fi

  # Identidade é REQUIRED — a LEITURA usa canuto_project_slug (postura de hot
  # path, com cache).
  if command -v canuto_project_slug >/dev/null 2>&1; then
    slug=$(canuto_project_slug "$root" 2>/dev/null || true)
    slug="${slug%%$'\n'*}"
  fi

  if [ -z "$slug" ]; then
    # Falha de identidade: NUNCA silêncio. Sem slug não se sabe qual vault ler,
    # então o brief diz que não consultou nada em vez de parecer vazio.
    _canuto_brief_status_write "" "" "unresolved" "" "" "identity" ""
    printf '── Canuto Vault Brief ──\n%s\n' "$CANUTO_BRIEF_MARK_IDENTITY_FAIL"
    return 0
  fi
  pop="identity"

  # "Declarado" = o CLAUDE.md do projeto afirma um project-slug. É o que separa
  # o estado (2) QUEBRADO do estado (3) FRESCO: quem declarou memória e não a
  # tem no disco está com o feeder desligado, não sem histórico.
  if [ -f "$root/CLAUDE.md" ]; then
    declared=$(grep -oE 'project-slug:[[:space:]]*[^[:space:]]+' "$root/CLAUDE.md" 2>/dev/null \
      | head -1 | sed -E 's/^project-slug:[[:space:]]*//' || true)
    declared="${declared%%$'\n'*}"
  fi

  # Identidade FRÁGIL: ler e escrever têm exigências diferentes (A3).
  # `canuto_require_project_slug` é a postura de ESCRITA — recusa slug de
  # último recurso, porque um slug por basename cria identidade nova a cada
  # worktree (a origem das 184 ilhas do vault). O brief é LEITURA: recusar
  # aqui apagaria um brief que funciona; então lemos com o slug do hot path e
  # AVISAMOS quando a postura estrita recusaria.
  # A resolução estrita não usa cache (~8 forks). Pré-checagem barata evita
  # pagá-la no caminho comum: quem declara project-slug OU mora num container
  # conhecido (workspaces/repos/...) já tem identidade durável por construção.
  # Só o caso suspeito pergunta ao dono da regra.
  if [ -z "$declared" ] && command -v canuto_require_project_slug >/dev/null 2>&1; then
    if [ -z "$(canuto_project_from_path "$root" 2>/dev/null || true)" ]; then
      strict_slug=$(canuto_require_project_slug "$root" 2>/dev/null || true)
      [ -n "${strict_slug%%$'\n'*}" ] || fragile=1
    fi
  fi

  # Path do vault. Expansão pura de CANUTO_VAULT_DIR (mesma decisão deliberada
  # que canuto-memory.sh documenta em canuto_vault_root: no hot path, a cópia
  # inline vale 1 fork a menos por hook). canuto_global_vault_dir NÃO serve
  # aqui: ele devolve vazio quando o diretório não existe, e é justamente a
  # ausência que este compositor precisa NOMEAR.
  vault="${CANUTO_VAULT_DIR:-$HOME/.canuto/vault}/projects/$slug"

  out="── Canuto Vault Brief ($slug) ──"
  if [ "$fragile" = 1 ]; then
    out="$out
⚠ identidade frágil: \"$slug\" veio do último recurso (basename) — cada worktree vira um vault novo (rode canuto-project-doctor)"
    broken="$broken,identity_fragile"
  fi

  if [ ! -d "$vault" ]; then
    if [ -n "$declared" ]; then
      out="$out
$CANUTO_BRIEF_MARK_VAULT_ABSENT ($declared) não encontrado em $vault"
      if [ "$declared" != "$slug" ]; then
        out="$out (slug resolvido: $slug)"
      fi
      out="$out
→ rode canuto-project-doctor: a memória do projeto está declarada e desligada."
      broken="vault"
      state="declared-absent"
    else
      out="$out
$CANUTO_BRIEF_MARK_FRESH"
      empty="vault"
      state="absent"
    fi
    _canuto_brief_status_write "$slug" "$vault" "$state" "$pop" "$empty" "$broken" ""
    printf '%s\n' "$out"
    return 0
  fi
  state="present"

  # ── Last session + Next entrypoint ────────────────────────────────────────
  # `ls -t` no diretório: sem glob (glob sem match degrada) e sem scan
  # recursivo. A nota mais recente é a mais recente — rerank de uso NÃO se
  # aplica aqui (a pergunta é "onde parei", não "o que costumo usar").
  sess_dir="$vault/sessions"
  if [ -d "$sess_dir" ]; then
    latest=$(ls -t "$sess_dir" 2>/dev/null | grep -m1 '\.md$' || true)
    latest="${latest%%$'\n'*}"
  fi
  if [ -n "$latest" ] && [ -f "$sess_dir/$latest" ]; then
    # sed único com `q` (1 fork) em vez de grep|cut (2); truncagem em bash puro.
    title=$(sed -n '/^# /{s/^# //p;q;}' "$sess_dir/$latest" 2>/dev/null || true)
    [ -n "$title" ] || title="${latest%.md}"
    title="${title:0:200}"
    out="$out
Last session: $title"
    pop="$pop,last_session"
    refs="$refs,session:$latest"
    entry=$(sed -n '/^next-entrypoint:/{s/^next-entrypoint:[[:space:]]*//p;q;}' "$sess_dir/$latest" 2>/dev/null || true)
    entry="${entry%\"}"
    entry="${entry#\"}"
    if [ -z "$entry" ]; then
      entry=$(awk '/^## Next Entrypoint/{f=1;next} f&&/^#/{exit} f&&NF{print;exit}' "$sess_dir/$latest" 2>/dev/null || true)
    fi
    entry="${entry%%$'\n'*}"
    if [ -n "$entry" ]; then
      entry="${entry:0:400}"
      out="$out
Next entrypoint: $entry"
      pop="$pop,next_entrypoint"
    else
      out="$out
Next entrypoint: $CANUTO_BRIEF_MARK_NO_ENTRY"
      empty="$empty,next_entrypoint"
    fi
  else
    out="$out
Last session: $CANUTO_BRIEF_MARK_NO_SESSION
Next entrypoint: $CANUTO_BRIEF_MARK_NO_ENTRY"
    empty="$empty,last_session,next_entrypoint"
  fi

  # ── Pending (cap 5) ───────────────────────────────────────────────────────
  dir="$vault/pending"
  n_total=0
  listed=""
  if [ -d "$dir" ]; then
    n_total=$(ls "$dir" 2>/dev/null | grep -c '\.md$' || true)
    case "$n_total" in ''|*[!0-9]*) n_total=0 ;; esac
    if [ "$n_total" -gt 0 ]; then
      listed=$(_canuto_brief_list "$dir" pending 5 "$slug")
    fi
  fi
  if [ -n "$listed" ]; then
    out="$out
Pending ($n_total):"
    while IFS= read -r f; do
      [ -n "$f" ] || continue
      t=$(sed -n '/^# /{s/^# //p;q;}' "$dir/$f" 2>/dev/null || true)
      [ -n "$t" ] || t="${f%.md}"
      out="$out
- ${t:0:160}"
      refs="$refs,pending:$f"
    done <<< "$listed"
    pop="$pop,pending"
  else
    out="$out
Pending: $CANUTO_BRIEF_MARK_NO_PENDING"
    empty="$empty,pending"
  fi

  # ── Instincts (cap 3) ─────────────────────────────────────────────────────
  dir="$vault/instincts"
  n_total=0
  listed=""
  if [ -d "$dir" ]; then
    n_total=$(ls "$dir" 2>/dev/null | grep -c '\.md$' || true)
    case "$n_total" in ''|*[!0-9]*) n_total=0 ;; esac
    if [ "$n_total" -gt 0 ]; then
      listed=$(_canuto_brief_list "$dir" instinct 3 "$slug")
    fi
  fi
  if [ -n "$listed" ]; then
    out="$out
Instincts ($n_total):"
    while IFS= read -r f; do
      [ -n "$f" ] || continue
      t=$(sed -n '/^# /{s/^# //p;q;}' "$dir/$f" 2>/dev/null || true)
      [ -n "$t" ] || t="${f%.md}"
      out="$out
- ${t:0:160}"
      refs="$refs,instinct:$f"
    done <<< "$listed"
    pop="$pop,instincts"
  else
    out="$out
Instincts: $CANUTO_BRIEF_MARK_NO_INSTINCT"
    empty="$empty,instincts"
  fi

  # Vault presente e TODAS as seções vazias: é aqui — e só aqui — que o vazio
  # é ambíguo. Pode ser projeto novo (honesto) ou fragmentação: o irmão tem as
  # notas e este slug ficou órfão. Quem sabe distinguir é o classificador (A3);
  # perguntar a ele custa forks, então só se pergunta no caso ambíguo, nunca no
  # caminho comum de um vault populado.
  if [ "$pop" = "identity" ] && command -v canuto_classify_vault >/dev/null 2>&1; then
    case "$(canuto_classify_vault "$slug" "$root" 2>/dev/null || true)" in
      *ORPHAN*)
        out="$out
⚠ vault órfão: outro slug guarda as notas deste projeto — este vazio não é honesto (rode canuto-project-doctor)"
        broken="$broken,vault_orphan"
        ;;
    esac
  fi

  out="$out
Vault: $vault"

  _canuto_brief_status_write "$slug" "$vault" "$state" \
    "${pop#,}" "${empty#,}" "${broken#,}" "${refs#,}"

  # Cap defensivo do total: ~40 linhas / ~3KB (ADR-0010: entry points, não dump).
  printf '%s\n' "$out" | head -40 | head -c 3000 || true
  return 0
}

# canuto_check_identity <root>
# DUAS pernas. Imprime "OK: ..." ou "FAIL: <motivo>"; retorna != 0 em FAIL.
# FAIL-CLOSED: qualquer erro interno é FAIL. "Não consegui determinar" NÃO é
# passe — foi exatamente assim que o eoc deixou uma instalação lobotomizada
# reportar HEALTHY (briefing-lifecycle-audit, root-cause #4).
canuto_check_identity() {
  local root="${1:-$(pwd)}"
  local text="" fresh="" hdr="" line="" tmp="" fake_slug="" fake_root=""
  local missing="" m="" bad_marker=""

  # ── Perna 0 — contrato dos marcadores (senão as pernas seguintes mentem) ──
  bad_marker=$(_canuto_brief_markers_ok) || {
    printf 'FAIL: marcador honesto vazio (%s) — o contrato de vazio-honesto está quebrado\n' \
      "${bad_marker:-desconhecido}"
    return 1
  }

  # ── Perna 1 — identidade: compõe contra o vault VIVO ─────────────────────
  # Não é um dry-run: é o mesmo compositor que o hook usa. Um gate que testa
  # outro caminho que o de produção não prova nada.
  text=$( unset CANUTO_BRIEF_STATUS_FILE; canuto_compose_brief "$root" 2>/dev/null || true )
  if [ -z "$text" ]; then
    printf 'FAIL: compositor devolveu string vazia para %s (brief mudo = lobotomia silenciosa)\n' "$root"
    return 1
  fi
  case "$text" in
    *"$CANUTO_BRIEF_MARK_IDENTITY_FAIL"*)
      printf 'FAIL: identidade não resolvida em %s — o vault não foi consultado\n' "$root"
      return 1
      ;;
  esac
  case "$text" in
    *"$CANUTO_BRIEF_MARK_VAULT_ABSENT"*)
      line=$(printf '%s\n' "$text" | grep -m1 "$CANUTO_BRIEF_MARK_VAULT_ABSENT" || true)
      printf 'FAIL: feeder declarado-e-ausente — %s\n' "${line:-vault declarado não encontrado}"
      return 1
      ;;
  esac
  hdr=$(printf '%s\n' "$text" | head -1 || true)

  # ── Perna 2 — controle positivo: compõe contra um vault FRESCO ───────────
  # Sem ela, um compositor quebrado que devolvesse "" para toda seção vazia
  # passaria na perna 1 de qualquer projeto populado. Aqui o vazio é a
  # resposta CORRETA, então os marcadores honestos têm de aparecer — é o que
  # separa "não há nada" de "não consegui ler".
  tmp=$(mktemp -d "${TMPDIR:-/tmp}/canuto-brief-selftest.XXXXXX" 2>/dev/null || true)
  if [ -z "$tmp" ] || [ ! -d "$tmp" ]; then
    printf 'FAIL: sandbox da perna de controle não pôde ser criada (fail-closed)\n'
    return 1
  fi
  fake_slug="canuto-brief-selftest"
  fake_root="$tmp/repo"
  mkdir -p "$fake_root" \
    "$tmp/vault/projects/$fake_slug/sessions" \
    "$tmp/vault/projects/$fake_slug/pending" \
    "$tmp/vault/projects/$fake_slug/instincts" 2>/dev/null || true
  printf 'project-slug: %s\n' "$fake_slug" > "$fake_root/CLAUDE.md" 2>/dev/null || true
  fresh=$(
    unset CANUTO_BRIEF_STATUS_FILE
    CANUTO_VAULT_DIR="$tmp/vault"; export CANUTO_VAULT_DIR
    CANUTO_SLUG_NO_CACHE=1; export CANUTO_SLUG_NO_CACHE
    canuto_compose_brief "$fake_root" 2>/dev/null || true
  )
  # Limpeza casada com o prefixo do mktemp — nunca um rm -rf de path solto.
  case "$tmp" in
    */canuto-brief-selftest.*) rm -rf "$tmp" 2>/dev/null || true ;;
  esac

  if [ -z "$fresh" ]; then
    printf 'FAIL: vault fresco produziu brief vazio (compositor não sabe renderizar o vazio)\n'
    return 1
  fi
  for m in "$CANUTO_BRIEF_MARK_NO_SESSION" "$CANUTO_BRIEF_MARK_NO_ENTRY" \
           "$CANUTO_BRIEF_MARK_NO_PENDING" "$CANUTO_BRIEF_MARK_NO_INSTINCT"; do
    case "$fresh" in
      *"$m"*) : ;;
      *) missing="$missing $m" ;;
    esac
  done
  if [ -n "$missing" ]; then
    printf 'FAIL: vault fresco não renderizou marcador honesto de vazio:%s\n' "$missing"
    return 1
  fi

  printf 'OK: %s | vazio honesto renderizado no controle (4 marcadores)\n' "${hdr:-identidade resolvida}"
  return 0
}

# ── CLI ─────────────────────────────────────────────────────────────────────
# `:-` em BASH_SOURCE: sob `zsh -u` a variável não existe e o teste abortaria o
# source (o framework roda em bash, mas hooks são lidos por ferramentas zsh).
if [ "${BASH_SOURCE[0]:-}" = "${0:-}" ]; then
  case "${1:-}" in
    brief)
      shift
      canuto_compose_brief "${1:-$(pwd)}"
      ;;
    check-identity)
      shift
      canuto_check_identity "${1:-$(pwd)}"
      ;;
    *)
      echo "uso: brief-compose.sh brief [root] | check-identity [root]" >&2
      exit 1
      ;;
  esac
fi
