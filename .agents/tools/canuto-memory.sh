#!/usr/bin/env bash

set -euo pipefail

# Diretório desta lib — usado só para o source preguiçoso de event-log.sh em
# canuto__emit_event. Expansão pura (sem fork): o `source` deste arquivo está
# no caminho de TODO hook. Sem BASH_SOURCE (zsh, `sh canuto-memory.sh`) cai
# para $0 e, se ainda assim não resolver, o emit degrada em nota de _health.
_CANUTO_MEMORY_LIB_SELF="${BASH_SOURCE[0]:-$0}"
_CANUTO_MEMORY_LIB_DIR="${_CANUTO_MEMORY_LIB_SELF%/*}"
[ "$_CANUTO_MEMORY_LIB_DIR" != "$_CANUTO_MEMORY_LIB_SELF" ] || _CANUTO_MEMORY_LIB_DIR="."

canuto_project_dir() {
  local dir="${1:-${CLAUDE_PROJECT_DIR:-$(pwd)}}"
  git -C "$dir" rev-parse --show-toplevel 2>/dev/null || printf '%s\n' "$dir"
}

# ---------------------------------------------------------------------------
# Resolução canônica de slug (Track B, auditoria 2026-08-01).
#
# Espelha a resolução do lado Node em ~/.canuto/bin/canuto-brain.mjs para que
# hooks shell e brain escrevam no MESMO projeto do vault (antes: cada worktree
# Conductor virava um slug novo — 184 ilhas no vault):
#   - slugify            <- canuto-brain.mjs slugify() (linhas ~57-65)
#   - colapso de container <- projectFromPath() + PROJECT_CONTAINER_SEGMENTS
#                             (linhas ~102-118): .../workspaces/<proj>/<wt> -> <proj>
#   - aliases semânticos <- <vault>/.project-aliases.json (linhas ~120-140)
#
# Precedência (canuto_project_slug):
#   1. override "project-slug:" do CLAUDE.md do toplevel — com guarda
#      anti-template: slug do framework num repo que não é o framework é
#      ignorado e registrado em <vault>/_health/slug-anomalies.jsonl
#      (contaminação real: CLAUDE.md copiado do template no repo mecesa).
#   2. colapso de container do path do toplevel.
#   4. fallback: basename do remote origin (sem .git); senão basename do
#      toplevel (comportamento antigo).
#   3. alias semântico aplicado sobre o candidato final de qualquer etapa.
#
# Env:
#   CANUTO_VAULT_DIR      raiz do vault (default: $HOME/.canuto/vault) — para testes
#   CANUTO_SLUG_NO_CACHE  =1 desativa cache/memo (para testes)
#
# Se PROJECT_CONTAINER_SEGMENTS mudar no canuto-brain.mjs, atualizar o `case`
# em canuto_project_from_path junto.
#
# INVARIANTE — NADA de identidade resolve no `source` (Fase 2 / eoc ADR-0015).
# Nenhuma resolução de slug, vault ou alias roda em source time: tudo acontece
# DENTRO de função, no momento da chamada. O único trabalho de source time é a
# detecção do flavor do `stat` (abaixo) e a expansão do diretório desta lib —
# ambos independentes de projeto. Racional: no edge-of-chaos, `sweep.py:34`
# cacheava o group em import time e a cópia stale escondeu 294 sessões perdidas
# (ADR-0015, "no module caches the result at import time"). O memo em processo
# de canuto_project_slug é chaveado pelo argumento (_CANUTO_SLUG_MEMO_DIR) e
# curto-circuitado por CANUTO_SLUG_NO_CACHE=1 — nunca vira estado global mudo.
# ---------------------------------------------------------------------------

canuto_slugify() {
  # Réplica do slugify() do canuto-brain.mjs: lowercase, remoção de acentos
  # (NFD + strip de combining marks), runs não-alfanuméricos viram "-", trim
  # de "-" nas pontas, máx 100 chars, fallback "item".
  local value="${1:-}"
  local ascii=""
  if [ -z "$value" ]; then
    printf 'item\n'
    return 0
  fi
  # iconv //TRANSLIT decompõe acento em marcador ASCII ("é" -> "'e",
  # "ã" -> "~a"); deletar os marcadores reproduz o strip de combining marks
  # do brain ("cartório" -> "cartorio"). ATENÇÃO: iconv do macOS pode sair
  # com rc!=0 ("invalid characters") MESMO tendo produzido o output inteiro —
  # por isso o fallback para o valor cru é por output vazio, não por rc.
  ascii=$(printf '%s' "$value" | iconv -f UTF-8 -t ASCII//TRANSLIT 2>/dev/null || true)
  [ -n "$ascii" ] || ascii="$value"
  # tr -d "'"'`~^"'  => deleta os 5 marcadores de acento: ' ` ~ ^ "
  ascii=$(printf '%s' "$ascii" \
    | tr -d "'"'`~^"' \
    | tr '[:upper:]' '[:lower:]' \
    | sed -E 's/[^a-z0-9]+/-/g; s/^-+//; s/-+$//' \
    | cut -c1-100)
  if [ -n "$ascii" ]; then
    printf '%s\n' "$ascii"
  else
    printf 'item\n'
  fi
}

canuto_project_from_path() {
  # Réplica do projectFromPath() do canuto-brain.mjs: divide o path em
  # segmentos, varre da direita para a esquerda (container mais profundo
  # vence) e devolve o slug do segmento seguinte a um container conhecido.
  # Sem match: imprime vazio.
  local value="${1:-}"
  local -a raw
  local -a parts
  local seg="" i=0 n=0
  raw=()
  parts=()
  IFS='/' read -r -a raw <<< "$value" || true
  n=${#raw[@]}
  i=0
  while [ "$i" -lt "$n" ]; do
    seg="${raw[$i]:-}"
    if [ -n "$seg" ]; then
      parts[${#parts[@]}]="$seg"
    fi
    i=$((i + 1))
  done
  n=${#parts[@]}
  i=$((n - 2))
  while [ "$i" -ge 0 ]; do
    case "${parts[$i]}" in
      workspaces|repos|projects|worktrees)  # PROJECT_CONTAINER_SEGMENTS do brain
        if [ -n "${parts[$((i + 1))]:-}" ]; then
          canuto_slugify "${parts[$((i + 1))]}"
          return 0
        fi
        ;;
    esac
    i=$((i - 1))
  done
  printf '\n'
}

canuto_alias_lookup() {
  # Consulta <vault>/.project-aliases.json (objeto JSON flat alias->canônico)
  # sem depender de jq. Arquivo ausente/malformado => vazio (sem alias).
  # A chave vem de canuto_slugify, logo é [a-z0-9-] — segura como ERE literal.
  local key="${1:-}"
  local file="${CANUTO_VAULT_DIR:-$HOME/.canuto/vault}/.project-aliases.json"
  local mapped=""
  if [ -z "$key" ] || [ ! -f "$file" ]; then
    printf '\n'
    return 0
  fi
  mapped=$(grep -oE "\"${key}\"[[:space:]]*:[[:space:]]*\"[^\"]*\"" "$file" 2>/dev/null \
    | head -1 \
    | sed -E 's/.*:[[:space:]]*"([^"]*)".*/\1/' || true)
  printf '%s\n' "$mapped"
}

# Flavor do stat detectado UMA vez no source (BSD -f no macOS, GNU -c no
# Linux) para o hot path não pagar tentativa-e-erro a cada chamada.
if stat -f %m / >/dev/null 2>&1; then
  _CANUTO_STAT_BSD=1
else
  _CANUTO_STAT_BSD=0
fi

canuto__mtime() {
  # mtime portátil; arquivo ausente => 0.
  if [ "${_CANUTO_STAT_BSD:-1}" = 1 ]; then
    stat -f %m "${1:-}" 2>/dev/null || printf '0\n'
  else
    stat -c %Y "${1:-}" 2>/dev/null || printf '0\n'
  fi
}

canuto__slug_token_compute() {
  # Seta _CANUTO_SLUG_TOKEN (mtime CLAUDE.md + mtime alias map) SEM subshell
  # de captura — chamada direta no shell corrente; hot path = 2 forks de stat.
  local project_dir="${1:-}"
  local alias_file="${CANUTO_VAULT_DIR:-$HOME/.canuto/vault}/.project-aliases.json"
  local t=""
  if [ "${_CANUTO_STAT_BSD:-1}" = 1 ]; then
    t=$( { stat -f %m "$project_dir/CLAUDE.md" 2>/dev/null || printf '0'; printf '.'; stat -f %m "$alias_file" 2>/dev/null || printf '0'; } ) || true
  else
    t=$( { stat -c %Y "$project_dir/CLAUDE.md" 2>/dev/null || printf '0'; printf '.'; stat -c %Y "$alias_file" 2>/dev/null || printf '0'; } ) || true
  fi
  # stat imprime newline após cada mtime; normaliza para "m1.m2" via expansão pura.
  _CANUTO_SLUG_TOKEN="${t//[^0-9.]/}"
  return 0
}

canuto__slug_cache_file_compute() {
  # Seta _CANUTO_SLUG_CACHE_FILE. Key derivada do toplevel SEM forks: path
  # sanitizado por expansão pura + comprimento como discriminador (truncado a
  # 200 chars por NAME_MAX=255). (cksum/id -u custavam ~5 forks por chamada.)
  local project_dir="${1:-}"
  local key="${project_dir//\//_}"
  _CANUTO_SLUG_CACHE_FILE="${TMPDIR:-/tmp}/canuto-slug-${UID:-0}-${#project_dir}-${key:0:200}"
  return 0
}

canuto__slug_cache_file() {
  canuto__slug_cache_file_compute "${1:-}"
  printf '%s\n' "$_CANUTO_SLUG_CACHE_FILE"
}

canuto__slug_is_safe() {
  # S5: slug vira COMPONENTE DE PATH de escrita no vault (projects/<slug>) e o
  # cache mora em /tmp, gravável por qualquer processo do usuário (cache
  # squatting). Aceita só [A-Za-z0-9._-] puro, não-vazio, ≤100 chars, sem
  # "/" (fora do charset), sem ".." e sem ser "." — o resto é recusado.
  # Vale ao LER e ao GRAVAR o cache, e no resultado final da resolução.
  local s="${1:-}"
  [ -n "$s" ] || return 1
  [ "${#s}" -le 100 ] || return 1
  case "$s" in
    .|*..*) return 1 ;;
    *[!A-Za-z0-9._-]*) return 1 ;;
  esac
  return 0
}

canuto__log_slug_anomaly() {
  # Best-effort: nunca falha nem bloqueia a resolução do slug.
  local project_dir="${1:-}" override="${2:-}"
  local health_dir="${CANUTO_VAULT_DIR:-$HOME/.canuto/vault}/_health"
  local ts="" esc_dir="" esc_override=""
  mkdir -p "$health_dir" 2>/dev/null || return 0
  ts=$(date -u +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || true)
  esc_dir=$(printf '%s' "$project_dir" | sed -e 's/\\/\\\\/g' -e 's/"/\\"/g' 2>/dev/null || true)
  esc_override=$(printf '%s' "$override" | sed -e 's/\\/\\\\/g' -e 's/"/\\"/g' 2>/dev/null || true)
  printf '{"ts":"%s","cwd":"%s","override":"%s","motivo":"template-slug-suspeito"}\n' \
    "$ts" "$esc_dir" "$esc_override" >> "$health_dir/slug-anomalies.jsonl" 2>/dev/null || true
  return 0
}

canuto__repo_is_framework() {
  # O repo "parece ser o framework" se QUALQUER identidade contiver
  # canuto-framework: basename do remote origin (sem .git); sem remote,
  # basename do toplevel; e o candidato do colapso de container — cobre
  # worktree Conductor do framework sem remote (workspaces/canuto-framework/<wt>).
  local project_dir="${1:-}"
  local remote_url="" ident="" collapsed=""
  remote_url=$(git -C "$project_dir" remote get-url origin 2>/dev/null || true)
  if [ -n "$remote_url" ]; then
    ident=$(basename "$remote_url" .git)
  else
    ident=$(basename "$project_dir")
  fi
  case "$ident" in
    *canuto-framework*) return 0 ;;
  esac
  collapsed=$(canuto_project_from_path "$project_dir")
  case "$collapsed" in
    *canuto-framework*) return 0 ;;
  esac
  return 1
}

canuto__slug_resolve() {
  # Resolução sem cache. $2=1 imprime cada etapa (modo explain/doctor) e a
  # linha final rotulada; $2=0 imprime só o slug.
  local project_dir="${1:-}"
  local explain="${2:-0}"
  local override="" candidate="" candidate_src="" aliased="" final="" remote_url=""

  if [ "$explain" = 1 ]; then
    printf 'project_dir: %s\n' "$project_dir"
  fi

  # Etapa 1 — override "project-slug:" do CLAUDE.md do toplevel
  if [ -f "$project_dir/CLAUDE.md" ]; then
    override=$(grep -oE 'project-slug:[[:space:]]*[^[:space:]]+' "$project_dir/CLAUDE.md" 2>/dev/null \
      | head -1 \
      | sed -E 's/^project-slug:[[:space:]]*//' || true)
    if [ "$explain" = 1 ]; then
      printf 'etapa1 override CLAUDE.md: %s\n' "${override:-"(presente, sem project-slug:)"}"
    fi
  else
    if [ "$explain" = 1 ]; then
      printf 'etapa1 override CLAUDE.md: (arquivo ausente)\n'
    fi
  fi

  # Guarda anti-template: slug do framework declarado num repo que não é o
  # framework => ignora o override e registra anomalia.
  if [ -n "$override" ]; then
    case "$override" in
      canuto-framework|canuto-framework-v1)
        if canuto__repo_is_framework "$project_dir"; then
          if [ "$explain" = 1 ]; then
            printf 'guarda anti-template: override "%s" e repo confirmado como framework -> honrado\n' "$override"
          fi
        else
          if [ "$explain" = 1 ]; then
            printf 'guarda anti-template: DISPAROU — override "%s" num repo que não parece canuto-framework -> ignorado; anomalia registrada em _health/slug-anomalies.jsonl\n' "$override"
          fi
          canuto__log_slug_anomaly "$project_dir" "$override"
          override=""
        fi
        ;;
      *)
        if [ "$explain" = 1 ]; then
          printf 'guarda anti-template: n/a (override não é slug de template)\n'
        fi
        ;;
    esac
  fi

  if [ -n "$override" ]; then
    # Etapa 3 sobre o override: alias mapeado vence (paridade com o brain,
    # que aplica canonicalProject a tudo); sem alias, override sai verbatim
    # (compat com o comportamento histórico).
    aliased=$(canuto_alias_lookup "$(canuto_slugify "$override")")
    if [ -n "$aliased" ]; then
      final=$(canuto_slugify "$aliased")
      if [ "$explain" = 1 ]; then
        printf 'etapa3 alias: %s -> %s\n' "$override" "$final"
      fi
    else
      final="$override"
      if [ "$explain" = 1 ]; then
        printf 'etapa3 alias: (sem entrada) -> override verbatim\n'
      fi
    fi
    # S5 (defesa em profundidade): o override verbatim era o vetor de path
    # traversal — "project-slug: ../../etc" saía daqui intacto.
    if ! canuto__slug_is_safe "$final"; then
      if [ "$explain" = 1 ]; then
        printf 'guarda de path: "%s" invalido como componente de path -> sanitizado\n' "$final"
      fi
      final=$(canuto_slugify "$final")
    fi
    if [ "$explain" = 1 ]; then
      printf 'slug: %s (fonte: override CLAUDE.md)\n' "$final"
    else
      printf '%s\n' "$final"
    fi
    return 0
  fi

  # Etapa 2 — colapso de container (projectFromPath do canuto-brain.mjs)
  candidate=$(canuto_project_from_path "$project_dir")
  if [ -n "$candidate" ]; then
    candidate_src="colapso-container"
  else
    # Etapa 4 — fallback: basename do remote origin; senão basename do toplevel
    remote_url=$(git -C "$project_dir" remote get-url origin 2>/dev/null || true)
    if [ -n "$remote_url" ]; then
      candidate=$(canuto_slugify "$(basename "$remote_url" .git)")
      candidate_src="remote-origin ($remote_url)"
    else
      candidate=$(canuto_slugify "$(basename "$project_dir")")
      candidate_src="basename-toplevel"
    fi
  fi
  if [ "$explain" = 1 ]; then
    printf 'etapa2/4 candidato: %s (via %s)\n' "$candidate" "$candidate_src"
  fi

  # Etapa 3 — alias semântico sobre o candidato
  aliased=$(canuto_alias_lookup "$candidate")
  if [ -n "$aliased" ]; then
    final=$(canuto_slugify "$aliased")
    if [ "$explain" = 1 ]; then
      printf 'etapa3 alias: %s -> %s\n' "$candidate" "$final"
    fi
  else
    final="$candidate"
    if [ "$explain" = 1 ]; then
      printf 'etapa3 alias: (sem entrada) -> %s\n' "$final"
    fi
  fi

  # S5 (defesa em profundidade): candidatos daqui já passam por canuto_slugify,
  # mas o resultado FINAL nunca sai sem a validação de componente de path.
  if ! canuto__slug_is_safe "$final"; then
    if [ "$explain" = 1 ]; then
      printf 'guarda de path: "%s" invalido como componente de path -> sanitizado\n' "$final"
    fi
    final=$(canuto_slugify "$final")
  fi
  if [ "$explain" = 1 ]; then
    printf 'slug: %s (fonte: %s)\n' "$final" "$candidate_src"
  else
    printf '%s\n' "$final"
  fi
  return 0
}

canuto_project_slug() {
  # Assinatura preservada: path opcional; sem argumento usa canuto_project_dir.
  # Cache em arquivo keyed por hash do toplevel, invalidado por mtime do
  # CLAUDE.md + mtime do .project-aliases.json (hooks chamam isto por evento).
  local project_dir="${1:-$(canuto_project_dir)}"
  local slug="" token="" cache_file="" cached_token="" cached_slug=""

  if [ "${CANUTO_SLUG_NO_CACHE:-0}" = "1" ]; then
    canuto__slug_resolve "$project_dir" 0
    return 0
  fi

  # Memo em processo (hooks de vida curta; evita re-resolver no mesmo shell).
  if [ "${_CANUTO_SLUG_MEMO_DIR:-}" = "$project_dir" ] && [ -n "${_CANUTO_SLUG_MEMO_VALUE:-}" ]; then
    printf '%s\n' "$_CANUTO_SLUG_MEMO_VALUE"
    return 0
  fi

  # Chamadas diretas (sem $()) mantêm o hot path em ~2 forks de stat.
  canuto__slug_token_compute "$project_dir"
  token="$_CANUTO_SLUG_TOKEN"
  canuto__slug_cache_file_compute "$project_dir"
  cache_file="$_CANUTO_SLUG_CACHE_FILE"

  if [ -f "$cache_file" ]; then
    IFS=$'\t' read -r cached_token cached_slug < "$cache_file" 2>/dev/null || true
    # S5: slug do cache de /tmp NUNCA é aceito verbatim (cache squatting =
    # path traversal de escrita no vault) — inválido ignora e recomputa.
    if [ "$cached_token" = "$token" ] && canuto__slug_is_safe "$cached_slug"; then
      _CANUTO_SLUG_MEMO_DIR="$project_dir"
      _CANUTO_SLUG_MEMO_VALUE="$cached_slug"
      printf '%s\n' "$cached_slug"
      return 0
    fi
  fi

  slug=$(canuto__slug_resolve "$project_dir" 0)
  # S5: a mesma validação na GRAVAÇÃO — cache nunca guarda slug fora do contrato.
  if canuto__slug_is_safe "$slug"; then
    printf '%s\t%s\n' "$token" "$slug" > "$cache_file" 2>/dev/null || true
  fi
  _CANUTO_SLUG_MEMO_DIR="$project_dir"
  _CANUTO_SLUG_MEMO_VALUE="$slug"
  printf '%s\n' "$slug"
}

canuto_project_slug_explain() {
  # Diagnóstico para o doctor: estado do cache + cada etapa da decisão.
  # Não lê nem escreve o cache (sempre resolve fresco).
  local project_dir="${1:-$(canuto_project_dir)}"
  local cache_file="" token="" cached_token="" cached_slug=""
  canuto__slug_cache_file_compute "$project_dir"
  cache_file="$_CANUTO_SLUG_CACHE_FILE"
  canuto__slug_token_compute "$project_dir"
  token="$_CANUTO_SLUG_TOKEN"
  if [ -f "$cache_file" ]; then
    IFS=$'\t' read -r cached_token cached_slug < "$cache_file" 2>/dev/null || true
    # S5: mesmo critério do caminho quente — cache com slug fora do contrato
    # não é "HIT valido" (e o valor suspeito não é ecoado no diagnóstico).
    if [ "$cached_token" = "$token" ] && canuto__slug_is_safe "$cached_slug"; then
      printf 'cache: HIT valido -> %s (%s)\n' "$cached_slug" "$cache_file"
    else
      printf 'cache: STALE (%s)\n' "$cache_file"
    fi
  else
    printf 'cache: ausente (%s)\n' "$cache_file"
  fi
  canuto__slug_resolve "$project_dir" 1
}

# ---------------------------------------------------------------------------
# Identidade em DUAS POSTURAS (Fase 2 A3, absorvido do edge-of-chaos ADR-0015
# "identity resolves at one fail-loud seam" + tools/_identity.py group()/
# require_group()).
#
#   LEITURA  (canuto_project_slug)          — degrada: sempre devolve algo, o
#                                             chamador rotula honestamente.
#   ESCRITA  (canuto_require_project_slug)  — falha alto: sem identidade
#                                             confiável, NÃO escreve.
#
# Por que duas: escrita com identidade chutada é contaminação entre projetos.
# Lá, a leitura "degradada quietinha" ("nothing new") escondeu 294 sessões
# nunca digeridas por dois dias. Aqui o equivalente é gravar sessão/pending no
# vault do projeto errado — e ninguém percebe até o vault estar fragmentado.
# ---------------------------------------------------------------------------

canuto_vault_root() {
  # Raiz do vault global. Uma única definição para o código novo; as cópias
  # inline em canuto_alias_lookup/__slug_token_compute/__log_slug_anomaly são
  # DELIBERADAS (hot path: expansão pura evita 1 fork por chamada de hook).
  printf '%s\n' "${CANUTO_VAULT_DIR:-$HOME/.canuto/vault}"
}

canuto__emit_event() {
  # Telemetria best-effort: NUNCA pode quebrar a resolução de identidade.
  # Source preguiçoso de event-log.sh (não em source time: event-log.sh faz
  # source de canuto-memory.sh quando canuto_project_dir não existe — como
  # aqui ele já existe, não há recursão). Sem lib, a degradação vira nota em
  # _health/missing-lib.jsonl: degradação nunca é silenciosa.
  local lib=""
  if ! command -v canuto_event_append >/dev/null 2>&1; then
    lib="${_CANUTO_MEMORY_LIB_DIR:-.}/event-log.sh"
    if [ -f "$lib" ]; then
      # shellcheck source=event-log.sh
      . "$lib" 2>/dev/null || true
    elif [ -n "${CLAUDE_PROJECT_DIR:-}" ] && [ -f "$CLAUDE_PROJECT_DIR/.agents/tools/event-log.sh" ]; then
      # shellcheck source=/dev/null
      . "$CLAUDE_PROJECT_DIR/.agents/tools/event-log.sh" 2>/dev/null || true
    elif [ -f "$HOME/.canuto/lib/event-log.sh" ]; then
      # shellcheck source=/dev/null
      . "$HOME/.canuto/lib/event-log.sh" 2>/dev/null || true
    fi
  fi
  if command -v canuto_event_append >/dev/null 2>&1; then
    canuto_event_append "$@" 2>/dev/null || true
  else
    canuto__missing_event_lib_note "${1:-UNKNOWN}"
  fi
  return 0
}

canuto__missing_event_lib_note() {
  # Mesmo padrão de _canuto_missing_lib_note dos hooks: uma nota por evento por
  # sessão, jamais falha.
  local marker="" health_dir=""
  marker="${TMPDIR:-/tmp}/canuto-missing-eventlib-${CLAUDE_SESSION_ID:-$PPID}-memory-${1:-x}"
  [ -e "$marker" ] && return 0
  : >"$marker" 2>/dev/null || true
  health_dir="$(canuto_vault_root)/_health"
  mkdir -p "$health_dir" 2>/dev/null || return 0
  printf '{"ts":"%s","hook":"canuto-memory","event":"%s","reason":"event-log-lib-missing"}\n' \
    "$(date -u +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || echo unknown)" "${1:-UNKNOWN}" \
    >>"$health_dir/missing-lib.jsonl" 2>/dev/null || true
  return 0
}

canuto_require_project_slug() {
  # POSTURA DE ESCRITA/INSTALL (eoc _identity.require_group).
  # Mesma resolução de canuto_project_slug, mas RECUSA o último recurso.
  #
  # Critério do que serve para escrever, declarado explicitamente: o slug
  # sobrevive a um `git worktree add`?
  #   - override "project-slug:" do CLAUDE.md  -> SIM (o worktree leva o
  #     CLAUDE.md junto; e a guarda anti-template já removeu o slug do
  #     template num repo que não é o framework)                     ACEITO
  #   - colapso de container (.../workspaces/<proj>/<wt>)  -> SIM (qualquer
  #     worktree dentro do container colapsa no mesmo <proj>)         ACEITO
  #   - basename do remote origin -> SIM (worktree compartilha o .git, logo o
  #     mesmo remote)                                                 ACEITO
  #   - basename do toplevel -> NÃO. `git worktree add ../damascus` num repo
  #     `canuto-framework` produziria o slug "damascus": identidade nova a
  #     cada worktree. Foi exatamente assim que o vault virou 184 ilhas.  RECUSADO
  #   - vazio                                                           RECUSADO
  #
  # Sucesso: imprime o slug em stdout, exit 0.
  # Falha:   stdout VAZIO, diagnóstico nomeando o gap em stderr, exit 1.
  #          Nunca imprime default silencioso — é isso que separa esta postura
  #          de canuto_project_slug.
  #
  # Não usa o cache de arquivo: precisa da FONTE, não só do valor, e escrita é
  # evento raro (init/closeout), não hot path.
  local project_dir="${1:-$(canuto_project_dir)}"
  local explain="" line="" rest="" slug="" src=""
  local override="" remote_url="" collapsed="" template_guard=""

  explain=$(canuto__slug_resolve "$project_dir" 1 2>/dev/null) || true
  line=$(printf '%s\n' "$explain" | grep -E '^slug: ' | tail -1 || true)
  if [ -n "$line" ]; then
    # Acoplamento local e deliberado ao formato de canuto__slug_resolve
    # (explain=1): "slug: <valor> (fonte: <origem>)". Mesmo arquivo, um dono só.
    rest="${line#slug: }"
    slug="${rest%% (fonte: *}"
    src="${rest#* (fonte: }"
    src="${src%\)}"
  fi

  case "$src" in
    override*|colapso-container|remote-origin*)
      if [ -n "$slug" ]; then
        printf '%s\n' "$slug"
        return 0
      fi
      ;;
  esac

  # ── Caminho de falha: nomear o gap, um por linha, com a ação certa ────────
  if [ -f "$project_dir/CLAUDE.md" ]; then
    override=$(grep -oE 'project-slug:[[:space:]]*[^[:space:]]+' "$project_dir/CLAUDE.md" 2>/dev/null \
      | head -1 | sed -E 's/^project-slug:[[:space:]]*//' || true)
  fi
  case "$explain" in *"guarda anti-template: DISPAROU"*) template_guard=1 ;; esac
  remote_url=$(git -C "$project_dir" remote get-url origin 2>/dev/null || true)
  collapsed=$(canuto_project_from_path "$project_dir" 2>/dev/null || true)

  {
    printf 'canuto_require_project_slug: identidade não resolvível para ESCRITA em %s\n' "$project_dir"
    if [ -n "$template_guard" ]; then
      printf '  - project-slug no CLAUDE.md: "%s" IGNORADO pela guarda anti-template (slug do template num repo que não é o framework)\n' "$override"
    elif [ -n "$override" ]; then
      printf '  - project-slug no CLAUDE.md: "%s" (não aproveitado — resolução caiu no fallback)\n' "$override"
    else
      printf '  - project-slug no CLAUDE.md: ausente\n'
    fi
    if [ -n "$remote_url" ]; then
      printf '  - remote origin: %s (não aproveitado)\n' "$remote_url"
    else
      printf '  - remote origin: ausente\n'
    fi
    if [ -n "$collapsed" ]; then
      printf '  - container conhecido: %s (não aproveitado)\n' "$collapsed"
    else
      printf '  - container conhecido (workspaces|repos|projects|worktrees): path fora de qualquer um\n'
    fi
    printf '  fallback disponível seria "%s" via %s — recusado: não sobrevive a `git worktree add` (eoc ADR-0015)\n' \
      "${slug:-<vazio>}" "${src:-<indeterminado>}"
    printf '  ação: rode canuto-init OU declare "project-slug: <slug>" no CLAUDE.md deste repo.\n'
  } >&2
  return 1
}

canuto__vault_notes_count() {
  # Quantas notas AUTORAIS o vault de um projeto tem. Só sessions/, pending/ e
  # instincts/ contam: audit/ e metrics/ são projeções mecânicas escritas por
  # hook e existiriam mesmo num vault sem uma linha de trabalho — contar por
  # elas daria POPULATED falso (e esconderia o órfão).
  local dir="${1:-}" n=""
  if [ -z "$dir" ] || [ ! -d "$dir" ]; then
    printf '0\n'
    return 0
  fi
  n=$(find "$dir/sessions" "$dir/pending" "$dir/instincts" -type f -name '*.md' 2>/dev/null \
    | wc -l | tr -d '[:space:]' || true)
  case "${n:-}" in ''|*[!0-9]*) n=0 ;; esac
  printf '%s\n' "$n"
}

canuto_alias_reverse_lookup() {
  # Sentido inverso de canuto_alias_lookup: dado o canônico, imprime TODOS os
  # aliases que apontam para ele (um por linha). Uma leitura só do arquivo —
  # o loop de irmãos não pode custar um grep por diretório do vault.
  # O valor vem de canuto_slugify, logo é [a-z0-9-]: seguro como ERE literal.
  local value="${1:-}"
  local file="$(canuto_vault_root)/.project-aliases.json"
  if [ -z "$value" ] || [ ! -f "$file" ]; then
    return 0
  fi
  grep -oE "\"[^\"]+\"[[:space:]]*:[[:space:]]*\"${value}\"" "$file" 2>/dev/null \
    | sed -E 's/^"([^"]+)".*/\1/' || true
  return 0
}

canuto_vault_sibling_candidate() {
  # Imprime "<irmão>\t<n-notas>" do vault irmão que provavelmente é o MESMO
  # produto, ou nada. Candidatos (nunca varre os 184 diretórios do vault):
  #   1. alias canônico do slug            (alias_lookup slug)
  #   2. aliases que apontam para o slug   (reverse slug)
  #   3. aliases irmãos do mesmo canônico  (reverse do canônico do slug)
  #   4. colapso de container do cwd       (canuto_project_from_path)
  # Vence o candidato com MAIS notas (o vault onde o trabalho de fato mora).
  local slug="${1:-}" project_dir="${2:-}"
  local projects_dir="" canonical="" collapsed="" cand="" n=0
  local best_name="" best_n=0
  local candidates=""

  [ -n "$slug" ] || return 0
  projects_dir="$(canuto_vault_root)/projects"
  [ -d "$projects_dir" ] || return 0

  canonical=$(canuto_alias_lookup "$slug" 2>/dev/null || true)
  collapsed=""
  if [ -n "$project_dir" ]; then
    collapsed=$(canuto_project_from_path "$project_dir" 2>/dev/null || true)
  fi
  candidates=$(
    {
      [ -n "$canonical" ] && printf '%s\n' "$canonical"
      canuto_alias_reverse_lookup "$slug"
      [ -n "$canonical" ] && canuto_alias_reverse_lookup "$canonical"
      [ -n "$collapsed" ] && printf '%s\n' "$collapsed"
      true
    } 2>/dev/null | sort -u || true
  )

  while IFS= read -r cand; do
    [ -n "$cand" ] || continue
    [ "$cand" != "$slug" ] || continue
    case "$cand" in .*|_*|*/*) continue ;; esac
    [ -d "$projects_dir/$cand" ] || continue
    n=$(canuto__vault_notes_count "$projects_dir/$cand")
    if [ "$n" -gt "$best_n" ]; then
      best_n="$n"
      best_name="$cand"
    fi
  done <<EOF
$candidates
EOF

  if [ -n "$best_name" ]; then
    printf '%s\t%s\n' "$best_name" "$best_n"
  fi
  return 0
}

canuto_classify_vault() {
  # POPULATED | FRESH | ORPHAN — um token em stdout, detalhe em stderr.
  # Absorvido de eoc tools/_validate.py::_classify_graph: "um install novo tem
  # grafo vazio-mas-alcançável, isso NÃO é falha; só é órfão quando o MEU
  # grupo está vazio E outro grupo tem dados".
  #   POPULATED  vault do slug tem >=1 nota em sessions|pending|instincts  (0)
  #   FRESH      vazio e nenhum irmão candidato — projeto novo de verdade   (0)
  #   ORPHAN     vazio MAS um irmão do mesmo produto tem notas              (1)
  # Exit 1 no ORPHAN porque é FAIL para quem gateia (doctor).
  local slug="${1:-}" project_dir="${2:-}"
  local dir="" n=0 sib="" sib_name="" sib_n=""

  [ -n "$project_dir" ] || project_dir=$(canuto_project_dir)
  if [ -z "$slug" ]; then
    slug=$(canuto_project_slug "$project_dir" 2>/dev/null || true)
  fi
  if [ -z "$slug" ]; then
    printf 'FRESH\n'
    printf 'canuto_classify_vault: slug não resolvido — nada a classificar\n' >&2
    return 0
  fi

  dir="$(canuto_vault_root)/projects/$slug"
  n=$(canuto__vault_notes_count "$dir")
  if [ "$n" -gt 0 ]; then
    printf 'POPULATED\n'
    printf 'vault "%s": %s nota(s) em %s\n' "$slug" "$n" "$dir" >&2
    # Fragmentação com AMBOS os lados cheios não é órfão (o meu tem dados), mas
    # também não pode passar calado: é o mesmo produto em dois vaults. Caso real
    # deste repo: canuto-framework-v1 (8 notas) + canuto-framework (7 notas).
    # Fica em stderr — o token de stdout e o exit 0 do contrato não mudam.
    sib=$(canuto_vault_sibling_candidate "$slug" "$project_dir")
    if [ -n "$sib" ]; then
      printf 'aviso de fragmentação: "%s" também tem %s nota(s) do mesmo produto — consolide ou registre um alias em .project-aliases.json\n' \
        "${sib%%	*}" "${sib##*	}" >&2
    fi
    return 0
  fi

  sib=$(canuto_vault_sibling_candidate "$slug" "$project_dir")
  if [ -n "$sib" ]; then
    sib_name="${sib%%	*}"
    sib_n="${sib##*	}"
    printf 'ORPHAN\n'
    printf 'vault ÓRFÃO: slug "%s" vazio mas "%s" tem %s nota(s) do mesmo produto — provável fragmentação; consolide os dois ou declare project-slug no CLAUDE.md\n' \
      "$slug" "$sib_name" "$sib_n" >&2
    canuto__emit_event VAULT_ORPHAN "slug=$slug" "sibling=$sib_name" \
      "sibling_notes=$sib_n" "vault=$(canuto_vault_root)" "project_dir=$project_dir"
    return 1
  fi

  printf 'FRESH\n'
  printf 'vault "%s" vazio e sem irmão candidato — projeto novo (popula na 1ª sessão)\n' "$slug" >&2
  return 0
}

canuto_fresh_clone_check() {
  # "Sou um clone do template ou um install vivo?" — o guard explícito do
  # AGENTS.md do edge-of-chaos ("if state/bootstrap.json does not exist and
  # nobody told you this is a live install, treat it as a fresh clone and ask
  # first"). Aqui o equivalente do bootstrap.json é: identidade declarada que
  # bate com o repo + vault com notas.
  #
  # Informativo por contrato: SEMPRE exit 0. Quem gateia é canuto-project-doctor.
  # Primeiro token da 1ª linha é o veredito legível por máquina:
  #   OK | TEMPLATE-CLONE | UNINITIALIZED | NOT-CANUTO
  local project_dir="${1:-}"
  local override="" slug="" vault_dir="" notes=0

  [ -n "$project_dir" ] || project_dir=$(canuto_project_dir)

  if [ -f "$project_dir/CLAUDE.md" ]; then
    override=$(grep -oE 'project-slug:[[:space:]]*[^[:space:]]+' "$project_dir/CLAUDE.md" 2>/dev/null \
      | head -1 | sed -E 's/^project-slug:[[:space:]]*//' || true)
  fi

  # (a) CLAUDE.md declara o slug do template num repo que não é o framework:
  #     é um clone/cópia do template, não um install. Escrever aqui contamina
  #     o vault do próprio framework (contaminação real: repo mecesa).
  case "$override" in
    canuto-framework|canuto-framework-v1)
      if ! canuto__repo_is_framework "$project_dir"; then
        printf 'TEMPLATE-CLONE: CLAUDE.md declara project-slug "%s", mas este repo não é o canuto-framework.\n' "$override"
        printf '  Efeito: sem a guarda anti-template, sessões deste projeto iriam para o vault do framework.\n'
        printf '  Ação: rode canuto-init neste repo OU troque "project-slug:" no CLAUDE.md pelo slug real do projeto.\n'
        return 0
      fi
      ;;
  esac

  if [ ! -d "$project_dir/.agents" ]; then
    printf 'NOT-CANUTO: %s não tem .agents/ — não é um install do framework (nada a verificar).\n' "$project_dir"
    return 0
  fi

  slug=$(canuto_project_slug "$project_dir" 2>/dev/null || true)
  vault_dir="$(canuto_vault_root)/projects/${slug:-__nao_resolvido__}"
  notes=$(canuto__vault_notes_count "$vault_dir")

  # (b) .agents/ existe, vault do slug resolvido está vazio e NADA foi
  #     declarado: o install nunca rodou de verdade aqui (ou o slug mudou
  #     debaixo dele). Não é erro fatal — é o estado "clone recém-baixado".
  if [ "${notes:-0}" -eq 0 ] && [ -z "$override" ]; then
    printf 'UNINITIALIZED: .agents/ existe mas o vault do slug "%s" está vazio e o CLAUDE.md não declara project-slug.\n' "${slug:-<não resolvido>}"
    printf '  Estado: %s (sem notas em sessions/pending/instincts).\n' "$vault_dir"
    printf '  Ação: rode canuto-init (ou declare "project-slug:" no CLAUDE.md) antes de confiar no briefing deste projeto.\n'
    return 0
  fi

  printf 'OK: install vivo — slug "%s", %s nota(s) em %s%s\n' \
    "${slug:-<não resolvido>}" "$notes" "$vault_dir" \
    "$([ -n "$override" ] && printf ', project-slug declarado' || printf '')"
  return 0
}

canuto_global_vault_dir() {
  local project_dir="${1:-$(canuto_project_dir)}"
  local slug
  slug=$(canuto_project_slug "$project_dir")
  # canuto_vault_root (não $HOME literal): sem isso, CANUTO_VAULT_DIR movia a
  # resolução de slug/alias para o sandbox mas o backend continuava apontando
  # para o vault real — testes verdes contra o estado errado.
  local dir="$(canuto_vault_root)/projects/$slug"

  if [ -d "$dir" ]; then
    printf '%s\n' "$dir"
  else
    printf '\n'
  fi
}

canuto_local_vault_dir() {
  local project_dir="${1:-$(canuto_project_dir)}"
  local dir="$project_dir/.agents/vault"

  if [ -d "$dir" ]; then
    printf '%s\n' "$dir"
  else
    printf '\n'
  fi
}

canuto_legacy_memory_dir() {
  local project_dir="${1:-$(canuto_project_dir)}"
  local dir="$project_dir/.agents/memory"

  if [ -d "$dir" ]; then
    printf '%s\n' "$dir"
  else
    printf '\n'
  fi
}

canuto_cache_dir() {
  local project_dir="${1:-$(canuto_project_dir)}"
  printf '%s\n' "$project_dir/.agents/.cache"
}

canuto_pending_sync_dir() {
  local project_dir="${1:-$(canuto_project_dir)}"
  printf '%s\n' "$(canuto_cache_dir "$project_dir")/pending-sync"
}

canuto_resolve_memory_backend() {
  local project_dir="${1:-$(canuto_project_dir)}"
  local global_vault=""
  local local_vault=""
  local legacy_memory=""

  global_vault=$(canuto_global_vault_dir "$project_dir")
  if [ -n "$global_vault" ]; then
    printf 'global\t%s\n' "$global_vault"
    return 0
  fi

  local_vault=$(canuto_local_vault_dir "$project_dir")
  if [ -n "$local_vault" ]; then
    printf 'local\t%s\n' "$local_vault"
    return 0
  fi

  legacy_memory=$(canuto_legacy_memory_dir "$project_dir")
  if [ -n "$legacy_memory" ]; then
    printf 'legacy\t%s\n' "$legacy_memory"
    return 0
  fi

  printf 'none\t\n'
}

canuto_resolve_vault_dir() {
  local project_dir="${1:-$(canuto_project_dir)}"
  local backend_kind=""
  local backend_dir=""

  IFS=$'\t' read -r backend_kind backend_dir < <(canuto_resolve_memory_backend "$project_dir")
  case "$backend_kind" in
    global|local)
      printf '%s\n' "$backend_dir"
      ;;
    *)
      printf '\n'
      ;;
  esac
}
