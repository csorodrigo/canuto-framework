#!/usr/bin/env bash
# =============================================================================
# canuto-update-all.sh — atualiza o framework em TODOS os projetos registrados.
#
# Descoberta: ~/.canuto/vault/projects/<slug>/project-path (gravado pelo hook
# SessionStart de cada projeto — um projeto entra no registro na primeira
# sessão aberta depois deste release). Paths extras podem ser passados como
# argumento. O repo do próprio framework é pulado (ele é a FONTE; o install.sh
# tem guarda própria contra rodar update dentro dele).
#
# Uso:
#   bash .agents/tools/canuto-update-all.sh              # atualiza desatualizados
#   bash .agents/tools/canuto-update-all.sh --dry-run    # só relata, não toca
#   bash .agents/tools/canuto-update-all.sh --force      # atualiza mesmo em dia
#   bash .agents/tools/canuto-update-all.sh --commit     # autoriza commit por projeto
#   bash .agents/tools/canuto-update-all.sh --channel edge # usa main explicitamente
#   bash .agents/tools/canuto-update-all.sh --version 1.8.0 # fixa releases/1.8.0
#   bash .agents/tools/canuto-update-all.sh --rollback 1.7.0 # rollback fixado
#   bash .agents/tools/canuto-update-all.sh /path/a /path/b   # paths extras
#   bash .agents/tools/canuto-update-all.sh --scan ~/projetos # bootstrap: acha
#       projetos com .agents/ sob o diretório (1ª rodada, registro ainda vazio)
#
# Por projeto: compara versão E source receipt local com o source selecionado e,
# quando desatualizado (ou --force), roda `bash install.sh --update --yes`
# DENTRO do projeto (o instalador do projeto se auto-atualiza do main antes de
# aplicar). Saída completa de cada projeto vai para um log em $TMPDIR.
#
# Contrato de segurança: NUNCA faz push. Por padrão também NÃO commita;
# `--commit` é a autorização explícita encaminhada ao install.sh. Projetos com
# working tree sujo são PULADOS — update no
# meio de trabalho não commitado mistura mudança de framework com mudança de
# produto.
#
# TTY e pipe: nenhum prompt. O script é 100% não-interativo por design
# (regra do CLAUDE.md: testado com `[[ -t 0 ]]` e stdin fechado).
# =============================================================================

set -uo pipefail

REPO_BASE="${CANUTO_REPO_BASE:-https://raw.githubusercontent.com/csorodrigo/canuto-framework}"
REPO_URL_OVERRIDE="${CANUTO_REPO_URL:-}"
REPO_RAW=""
SOURCE_KIND=""
SOURCE_REF=""
SOURCE_CHANNEL=""
SOURCE_VERSION=""
CLI_SOURCE_SELECTOR_COUNT=0
CLI_SOURCE_CHANNEL=""
CLI_SOURCE_VERSION=""
CLI_SOURCE_REF=""
ROLLBACK=0
VAULT_ROOT="${CANUTO_VAULT_DIR:-$HOME/.canuto/vault}"

GREEN='\033[0;32m'; YELLOW='\033[1;33m'; CYAN='\033[0;36m'; RED='\033[0;31m'; RESET='\033[0m'
log()  { echo -e "${CYAN}[update-all]${RESET} $1"; }
ok()   { echo -e "${GREEN}[update-all]${RESET} ✓ $1"; }
warn() { echo -e "${YELLOW}[update-all]${RESET} ⚠ $1"; }
err()  { echo -e "${RED}[update-all]${RESET} ✗ $1"; }


validate_channel() { case "$1" in stable|edge) return 0 ;; *) return 1 ;; esac; }
validate_version() { [[ "$1" =~ ^[0-9]+\.[0-9]+\.[0-9]+([.-][A-Za-z0-9][A-Za-z0-9.-]*)?$ ]]; }
validate_ref() {
  [ -n "$1" ] && [ "${#1}" -le 160 ] || return 1
  case "$1" in /*|*..*|*//*|*[^A-Za-z0-9._/-]*) return 1 ;; esac
  return 0
}
set_source_selector() {
  CLI_SOURCE_SELECTOR_COUNT=$((CLI_SOURCE_SELECTOR_COUNT + 1))
  [ "$CLI_SOURCE_SELECTOR_COUNT" -le 1 ] || { err "use só um entre --channel, --version, --ref e --rollback"; exit 64; }
  case "$1" in channel) CLI_SOURCE_CHANNEL="$2" ;; version) CLI_SOURCE_VERSION="$2" ;; ref) CLI_SOURCE_REF="$2" ;; esac
}
resolve_source() {
  local env_kind="${CANUTO_SOURCE_KIND:-}"
  local env_ref="${CANUTO_SOURCE_REF:-}"
  local env_channel="${CANUTO_SOURCE_CHANNEL:-${CANUTO_CHANNEL:-}}"
  local env_version="${CANUTO_SOURCE_VERSION:-${CANUTO_VERSION:-}}"
  if [ -n "$REPO_URL_OVERRIDE" ]; then
    [ "$CLI_SOURCE_SELECTOR_COUNT" -eq 0 ] || { err "CANUTO_REPO_URL não combina com seletor CLI"; exit 64; }
    SOURCE_KIND="${env_kind:-custom}"; SOURCE_REF="${env_ref:-custom}"
    SOURCE_CHANNEL="$env_channel"; SOURCE_VERSION="$env_version"
    REPO_RAW="${REPO_URL_OVERRIDE%/}"
    return 0
  fi
  if [ -n "$CLI_SOURCE_CHANNEL" ]; then
    validate_channel "$CLI_SOURCE_CHANNEL" || { err "--channel deve ser stable ou edge"; exit 64; }
    SOURCE_CHANNEL="$CLI_SOURCE_CHANNEL"; SOURCE_KIND="$CLI_SOURCE_CHANNEL"
    [ "$CLI_SOURCE_CHANNEL" = stable ] && SOURCE_REF=stable || SOURCE_REF=main
  elif [ -n "$CLI_SOURCE_VERSION" ]; then
    validate_version "$CLI_SOURCE_VERSION" || { err "versão inválida: $CLI_SOURCE_VERSION"; exit 64; }
    SOURCE_VERSION="$CLI_SOURCE_VERSION"; SOURCE_KIND=version; SOURCE_REF="releases/$CLI_SOURCE_VERSION"
  elif [ -n "$CLI_SOURCE_REF" ]; then
    validate_ref "$CLI_SOURCE_REF" || { err "ref inválida: $CLI_SOURCE_REF"; exit 64; }
    SOURCE_KIND=ref; SOURCE_REF="$CLI_SOURCE_REF"
  elif [ -n "$env_ref" ]; then
    validate_ref "$env_ref" || { err "CANUTO_SOURCE_REF inválida"; exit 64; }
    SOURCE_KIND="${env_kind:-ref}"; SOURCE_REF="$env_ref"; SOURCE_CHANNEL="$env_channel"; SOURCE_VERSION="$env_version"
  elif [ -n "$env_version" ]; then
    validate_version "$env_version" || { err "CANUTO_VERSION inválida"; exit 64; }
    SOURCE_VERSION="$env_version"; SOURCE_KIND=version; SOURCE_REF="releases/$env_version"
  else
    SOURCE_CHANNEL="${env_channel:-stable}"
    validate_channel "$SOURCE_CHANNEL" || { err "CANUTO_CHANNEL deve ser stable ou edge"; exit 64; }
    SOURCE_KIND="$SOURCE_CHANNEL"; [ "$SOURCE_CHANNEL" = stable ] && SOURCE_REF=stable || SOURCE_REF=main
  fi
  validate_ref "$SOURCE_REF" || { err "source ref resolvida é inválida: $SOURCE_REF"; exit 64; }
  REPO_RAW="${REPO_BASE%/}/$SOURCE_REF"
}
receipt_ref() {
  local receipt="$1"
  [ -f "$receipt" ] || return 1
  sed -n 's/^[[:space:]]*"sourceRef":[[:space:]]*"\([^"]*\)".*/\1/p' "$receipt" | head -1
}

DRY_RUN=0
FORCE=0
COMMIT=0
COMMIT_POLICY="default"
EXTRA_PATHS=()
SCAN_DIRS=()
while [ $# -gt 0 ]; do
  case "$1" in
    --dry-run) DRY_RUN=1 ;;
    --force)   FORCE=1 ;;
    --commit)
      [ "$COMMIT_POLICY" != "no-commit" ] || { err "--commit conflita com --no-commit"; exit 64; }
      COMMIT=1; COMMIT_POLICY="commit"
      ;;
    --no-commit)
      [ "$COMMIT_POLICY" != "commit" ] || { err "--no-commit conflita com --commit"; exit 64; }
      COMMIT=0; COMMIT_POLICY="no-commit"
      ;;
    --channel)
      shift; [ -n "${1:-}" ] || { err "--channel exige stable ou edge"; exit 64; }
      set_source_selector channel "$1"
      ;;
    --version)
      shift; [ -n "${1:-}" ] || { err "--version exige semver"; exit 64; }
      set_source_selector version "$1"
      ;;
    --ref)
      shift; [ -n "${1:-}" ] || { err "--ref exige uma ref Git"; exit 64; }
      set_source_selector ref "$1"
      ;;
    --rollback)
      shift; [ -n "${1:-}" ] || { err "--rollback exige semver"; exit 64; }
      ROLLBACK=1
      set_source_selector version "$1"
      ;;
    --scan)
      # Bootstrap do registro: varre um diretório-contêiner atrás de projetos
      # com .agents/. É o caminho para a PRIMEIRA rodada em máquinas cujos
      # projetos ainda não se registraram (o registro passa a acontecer no
      # install/update e nas sessões seguintes).
      shift
      [ -n "${1:-}" ] || { err "--scan exige um diretório"; exit 64; }
      SCAN_DIRS+=("$1")
      ;;
    --help|-h)
      sed -n '3,30p' "$0" | sed 's/^# \{0,1\}//'
      exit 0
      ;;
    -*)
      err "flag desconhecida: $1"; exit 64 ;;
    *) EXTRA_PATHS+=("$1") ;;
  esac
  shift
done

resolve_source
log "source selecionado: $SOURCE_KIND ($SOURCE_REF)"

# ── Versão remota (uma busca só para a rodada inteira) ──────────────────────
fetch_remote_version() {
  if [ -n "${CANUTO_SOURCE_DIR:-}" ] && [ -f "$CANUTO_SOURCE_DIR/.agents/VERSION" ]; then
    head -1 "$CANUTO_SOURCE_DIR/.agents/VERSION" 2>/dev/null
    return 0
  fi
  if command -v curl >/dev/null 2>&1; then
    curl -fsSL -m 10 "$REPO_RAW/.agents/VERSION" 2>/dev/null | head -1
  elif command -v wget >/dev/null 2>&1; then
    wget -q -T 10 "$REPO_RAW/.agents/VERSION" -O - 2>/dev/null | head -1
  fi
}

REMOTE_VERSION="$(fetch_remote_version | tr -d '[:space:]')"
if [ -z "$REMOTE_VERSION" ]; then
  err "não consegui ler a versão remota ($REPO_RAW/.agents/VERSION). Offline? Abortando sem tocar em nada."
  exit 1
fi
log "versão remota do framework: $REMOTE_VERSION — source: $SOURCE_REF"

# ── Descoberta de projetos ──────────────────────────────────────────────────
# Registro do vault + paths explícitos, deduplicado. Cada candidato só entra
# se o diretório existir e tiver .agents/ (registro pode apontar para projeto
# movido/apagado — isso vira status, não erro fatal).
CANDIDATES=()
if [ -d "$VAULT_ROOT/projects" ]; then
  for f in "$VAULT_ROOT/projects"/*/project-path; do
    [ -f "$f" ] || continue
    p="$(head -1 "$f" 2>/dev/null)"
    [ -n "$p" ] && CANDIDATES+=("$p")
  done
fi
if [ "${#EXTRA_PATHS[@]}" -gt 0 ]; then
  CANDIDATES+=("${EXTRA_PATHS[@]}")
fi
if [ "${#SCAN_DIRS[@]}" -gt 0 ]; then
  for d in "${SCAN_DIRS[@]}"; do
    [ -d "$d" ] || { warn "--scan: $d não existe — ignorado"; continue; }
    # -maxdepth 4 cobre contêiner/projeto(/worktree); prune de node_modules e
    # .git evita varrer o mundo. IFS por linha: path com espaço sobrevive.
    while IFS= read -r agents_dir; do
      [ -n "$agents_dir" ] && CANDIDATES+=("${agents_dir%/.agents}")
    done < <(find "$d" -maxdepth 4 \( -name node_modules -o -name .git \) -prune \
             -o -type d -name .agents -print 2>/dev/null)
  done
fi

if [ "${#CANDIDATES[@]}" -eq 0 ]; then
  warn "nenhum projeto registrado em $VAULT_ROOT/projects/*/project-path e nenhum path passado."
  warn "bootstrap: rode com --scan <dir-dos-projetos>, ou passe os paths como argumento."
  warn "(daqui em diante, install/update e sessões registram cada projeto sozinhos)"
  exit 0
fi

# dedup preservando ordem
PROJECTS=()
for p in "${CANDIDATES[@]}"; do
  dup=0
  for q in "${PROJECTS[@]:-}"; do [ "$p" = "$q" ] && dup=1 && break; done
  [ "$dup" = 0 ] && PROJECTS+=("$p")
done

# mktemp -d, NUNCA path previsível com mkdir -p: um diretório pré-criado por
# outro usuário em /tmp (canuto-update-all-<pid> é adivinhável) seria dele —
# e este script grava e EXECUTA um install.sh aqui dentro. mktemp cria com
# modo 700 e falha se não conseguir; sem mktemp, aborta.
LOG_DIR=$(mktemp -d "${TMPDIR:-/tmp}/canuto-update-all.XXXXXX" 2>/dev/null) || LOG_DIR=""
if [ -z "$LOG_DIR" ]; then
  err "mktemp indisponível ou falhou — sem diretório de trabalho seguro. Abortando."
  exit 1
fi

# Instalador FRESCO, baixado UMA vez e usado em todos os projetos. Nunca o
# install.sh de cada projeto: (a) o dele pode ser antigo, com FRAMEWORK_FILES
# defasada — o update rodaria sem os arquivos novos; (b) rodar o script que o
# próprio update sobrescreve era o bug do "unexpected EOF" (exit sujo num
# update bem-sucedido). O install.sh do projeto é atualizado como ARQUIVO,
# nunca executado por aqui.
FRESH_INSTALLER="$LOG_DIR/install.sh"
if [ -n "${CANUTO_SOURCE_DIR:-}" ] && [ -f "$CANUTO_SOURCE_DIR/install.sh" ]; then
  cp "$CANUTO_SOURCE_DIR/install.sh" "$FRESH_INSTALLER"
elif command -v curl >/dev/null 2>&1; then
  curl -fsSL -m 30 "$REPO_RAW/install.sh" -o "$FRESH_INSTALLER" 2>/dev/null || true
elif command -v wget >/dev/null 2>&1; then
  wget -q -T 30 "$REPO_RAW/install.sh" -O "$FRESH_INSTALLER" 2>/dev/null || true
fi
if [ ! -s "$FRESH_INSTALLER" ] || ! bash -n "$FRESH_INSTALLER" 2>/dev/null; then
  err "não consegui obter um install.sh íntegro de $SOURCE_REF. Abortando sem tocar em nada."
  exit 1
fi
# O instalador que RODA já é o fresco — ele não precisa se auto-renovar.
export CANUTO_BOOTSTRAPPED=1
export CANUTO_REPO_URL="$REPO_RAW"
export CANUTO_SOURCE_KIND="$SOURCE_KIND"
export CANUTO_SOURCE_REF="$SOURCE_REF"
export CANUTO_SOURCE_CHANNEL="$SOURCE_CHANNEL"
export CANUTO_SOURCE_VERSION="$SOURCE_VERSION"
SOURCE_SUPPORTS_RECEIPT=0
grep -q 'SOURCE-RECEIPT.json' "$FRESH_INSTALLER" 2>/dev/null && SOURCE_SUPPORTS_RECEIPT=1

# ── Loop principal ──────────────────────────────────────────────────────────
REPORT=()   # linhas "status|projeto|antes|depois|nota"
add_report() { REPORT+=("$1|$2|$3|$4|$5"); }

PROJ_IDX=0
for proj in "${PROJECTS[@]}"; do
  PROJ_IDX=$((PROJ_IDX + 1))
  name="$(basename "$proj")"

  if [ ! -d "$proj" ]; then
    add_report "SKIP" "$name" "-" "-" "path não existe: $proj"
    continue
  fi
  if [ ! -d "$proj/.agents" ]; then
    add_report "SKIP" "$name" "-" "-" "sem .agents/ (não é install do framework)"
    continue
  fi

  # A fonte nunca atualiza a si mesma por aqui. MESMO critério do guard do
  # install.sh (grep em QUALQUER remote, não só basename do origin): critérios
  # diferentes deixavam um fork renomeado passar por aqui e abortar lá dentro
  # — PARCIAL eterno com nota enganosa.
  if git -C "$proj" remote -v 2>/dev/null | grep -q "canuto-framework"; then
    add_report "SKIP" "$name" "-" "-" "repo do framework (fonte) — $proj"
    continue
  fi

  local_ver="$(head -1 "$proj/.agents/VERSION" 2>/dev/null | tr -d '[:space:]')"
  [ -n "$local_ver" ] || local_ver="?"
  local_ref="$(receipt_ref "$proj/.agents/SOURCE-RECEIPT.json" 2>/dev/null || true)"
  source_current=0
  if [ "$SOURCE_SUPPORTS_RECEIPT" -eq 1 ]; then
    [ "$local_ref" = "$SOURCE_REF" ] && source_current=1
  else
    source_current=1
  fi

  # Trabalho em curso = pular (nunca misturar update com mudança de produto) —
  # checado ANTES do dry-run e do check de versão, para o dry-run prometer
  # exatamente o que a rodada real faria. Só MODIFICAÇÕES RASTREADAS contam
  # (-uno): o próprio install.sh deixa arquivos untracked para trás.
  if [ -n "$(git -C "$proj" status --porcelain -uno 2>/dev/null)" ]; then
    if [ "$local_ver" = "$REMOTE_VERSION" ] && [ "$source_current" -eq 1 ] && [ "$FORCE" = 0 ]; then
      add_report "OK" "$name" "$local_ver" "$local_ver" "já na versão e source remotos (árvore suja; source=$SOURCE_REF) — $proj"
    else
      add_report "SKIP" "$name" "$local_ver" "-" "mudanças não commitadas — commit/stash antes — $proj"
    fi
    continue
  fi

  if [ "$local_ver" = "$REMOTE_VERSION" ] && [ "$source_current" -eq 1 ] && [ "$FORCE" = 0 ]; then
    add_report "OK" "$name" "$local_ver" "$local_ver" "já na versão e source remotos (source=$SOURCE_REF) — $proj"
    continue
  fi

  if [ "$DRY_RUN" = 1 ]; then
    add_report "PENDENTE" "$name" "$local_ver" "$REMOTE_VERSION" "dry-run: atualizaria $local_ref → $SOURCE_REF — $proj"
    continue
  fi

  log "atualizando $name ($local_ver/$local_ref → $REMOTE_VERSION/$SOURCE_REF)…"
  # Índice no nome do log: dois projetos com o mesmo basename (ex.: web/ em
  # contêineres diferentes) não podem sobrescrever o log um do outro.
  plog="$LOG_DIR/$PROJ_IDX-$name.log"
  # </dev/null é obrigatório: o repair_runtime do install.sh tem prompts crus
  # guardados por [[ -t 0 ]] (API key do Obsidian, "install Codex?") que o
  # --yes NÃO cobre — com o stdin do TTY herdado, o prompt iria para o log e
  # a rodada congelaria em silêncio no primeiro projeto.
  UPDATE_INSTALL_ARGS=(--update --yes)
  [ "$COMMIT" -eq 1 ] && UPDATE_INSTALL_ARGS+=(--commit)
  if (cd "$proj" && bash "$FRESH_INSTALLER" "${UPDATE_INSTALL_ARGS[@]}" </dev/null) >"$plog" 2>&1; then
    new_ver="$(head -1 "$proj/.agents/VERSION" 2>/dev/null | tr -d '[:space:]')"
    new_ref="$(receipt_ref "$proj/.agents/SOURCE-RECEIPT.json" 2>/dev/null || true)"
    receipt_ok=1
    if [ "$SOURCE_SUPPORTS_RECEIPT" -eq 1 ] && [ "$new_ref" != "$SOURCE_REF" ]; then receipt_ok=0; fi
    commit_note=""
    [ "$COMMIT" -eq 1 ] || commit_note="; mudanças não commitadas (--commit não informado)"
    if [ "$new_ver" = "$REMOTE_VERSION" ] && [ "$receipt_ok" -eq 1 ]; then
      add_report "ATUALIZADO" "$name" "$local_ver" "$new_ver" "source: ${new_ref:-legacy}/$SOURCE_REF; log: $plog$commit_note"
    else
      # O instalador rodou mas o carimbo não avançou (ex.: install.sh do
      # projeto anterior a este release, sem .agents/VERSION na lista).
      # Chamar isso de ATUALIZADO esconderia exatamente o drift que o
      # comando existe para eliminar.
      add_report "PARCIAL" "$name" "$local_ver" "${new_ver:-?}" "instalador aplicado, mas VERSION/receipt não convergiu para $REMOTE_VERSION/$SOURCE_REF; obtido ${new_ver:-?}/${new_ref:-ausente}; log: $plog$commit_note"
    fi
  else
    add_report "FALHA" "$name" "$local_ver" "-" "install.sh --update falhou — log: $plog"
  fi
done

# ── Relatório ───────────────────────────────────────────────────────────────
echo ""
echo -e "${CYAN}━━━ canuto update-all — relatório ($SOURCE_KIND:$SOURCE_REF, versão: $REMOTE_VERSION) ━━━${RESET}"
printf '%-11s %-28s %-9s %-9s %s\n' "STATUS" "PROJETO" "ANTES" "DEPOIS" "NOTA"
FAILURES=0
for line in "${REPORT[@]:-}"; do
  IFS='|' read -r st nm before after note <<< "$line"
  case "$st" in
    ATUALIZADO) color="$GREEN" ;;
    FALHA)      color="$RED"; FAILURES=$((FAILURES + 1)) ;;
    PARCIAL)    color="$YELLOW" ;;
    PENDENTE)   color="$YELLOW" ;;
    SKIP)       color="$YELLOW" ;;
    *)          color="$RESET" ;;
  esac
  printf "${color}%-11s${RESET} %-28s %-9s %-9s %s\n" "$st" "$nm" "$before" "$after" "$note"
done
echo ""
if [ "$FAILURES" -gt 0 ]; then
  err "$FAILURES projeto(s) falharam — ver logs em $LOG_DIR"
  exit 1
fi
ok "rodada concluída. Logs em $LOG_DIR"
exit 0
