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
#   bash .agents/tools/canuto-update-all.sh /path/a /path/b   # paths extras
#   bash .agents/tools/canuto-update-all.sh --scan ~/projetos # bootstrap: acha
#       projetos com .agents/ sob o diretório (1ª rodada, registro ainda vazio)
#
# Por projeto: compara .agents/VERSION local com o VERSION remoto do main e,
# quando desatualizado (ou --force), roda `bash install.sh --update --yes`
# DENTRO do projeto (o instalador do projeto se auto-atualiza do main antes de
# aplicar). Saída completa de cada projeto vai para um log em $TMPDIR.
#
# Contrato de segurança: NUNCA faz push. O commit local é o do próprio
# install.sh (--yes). Projetos com working tree sujo são PULADOS — update no
# meio de trabalho não commitado mistura mudança de framework com mudança de
# produto.
#
# TTY e pipe: nenhum prompt. O script é 100% não-interativo por design
# (regra do CLAUDE.md: testado com `[[ -t 0 ]]` e stdin fechado).
# =============================================================================

set -uo pipefail

REPO_RAW="${CANUTO_REPO_URL:-https://raw.githubusercontent.com/csorodrigo/canuto-framework/main}"
VAULT_ROOT="${CANUTO_VAULT_DIR:-$HOME/.canuto/vault}"

GREEN='\033[0;32m'; YELLOW='\033[1;33m'; CYAN='\033[0;36m'; RED='\033[0;31m'; RESET='\033[0m'
log()  { echo -e "${CYAN}[update-all]${RESET} $1"; }
ok()   { echo -e "${GREEN}[update-all]${RESET} ✓ $1"; }
warn() { echo -e "${YELLOW}[update-all]${RESET} ⚠ $1"; }
err()  { echo -e "${RED}[update-all]${RESET} ✗ $1"; }

DRY_RUN=0
FORCE=0
EXTRA_PATHS=()
SCAN_DIRS=()
while [ $# -gt 0 ]; do
  case "$1" in
    --dry-run) DRY_RUN=1 ;;
    --force)   FORCE=1 ;;
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
log "versão remota do framework: $REMOTE_VERSION"

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
  err "não consegui obter um install.sh íntegro do main. Abortando sem tocar em nada."
  exit 1
fi
# O instalador que RODA já é o fresco — ele não precisa se auto-renovar.
export CANUTO_BOOTSTRAPPED=1

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

  # Trabalho em curso = pular (nunca misturar update com mudança de produto) —
  # checado ANTES do dry-run e do check de versão, para o dry-run prometer
  # exatamente o que a rodada real faria. Só MODIFICAÇÕES RASTREADAS contam
  # (-uno): o próprio install.sh deixa arquivos untracked para trás.
  if [ -n "$(git -C "$proj" status --porcelain -uno 2>/dev/null)" ]; then
    if [ "$local_ver" = "$REMOTE_VERSION" ] && [ "$FORCE" = 0 ]; then
      add_report "OK" "$name" "$local_ver" "$local_ver" "já na versão remota (árvore suja) — $proj"
    else
      add_report "SKIP" "$name" "$local_ver" "-" "mudanças não commitadas — commit/stash antes — $proj"
    fi
    continue
  fi

  if [ "$local_ver" = "$REMOTE_VERSION" ] && [ "$FORCE" = 0 ]; then
    add_report "OK" "$name" "$local_ver" "$local_ver" "já na versão remota — $proj"
    continue
  fi

  if [ "$DRY_RUN" = 1 ]; then
    add_report "PENDENTE" "$name" "$local_ver" "$REMOTE_VERSION" "dry-run: atualizaria — $proj"
    continue
  fi

  log "atualizando $name ($local_ver → $REMOTE_VERSION)…"
  # Índice no nome do log: dois projetos com o mesmo basename (ex.: web/ em
  # contêineres diferentes) não podem sobrescrever o log um do outro.
  plog="$LOG_DIR/$PROJ_IDX-$name.log"
  # </dev/null é obrigatório: o repair_runtime do install.sh tem prompts crus
  # guardados por [[ -t 0 ]] (API key do Obsidian, "install Codex?") que o
  # --yes NÃO cobre — com o stdin do TTY herdado, o prompt iria para o log e
  # a rodada congelaria em silêncio no primeiro projeto.
  if (cd "$proj" && bash "$FRESH_INSTALLER" --update --yes </dev/null) >"$plog" 2>&1; then
    new_ver="$(head -1 "$proj/.agents/VERSION" 2>/dev/null | tr -d '[:space:]')"
    if [ "$new_ver" = "$REMOTE_VERSION" ]; then
      add_report "ATUALIZADO" "$name" "$local_ver" "$new_ver" "log: $plog"
    else
      # O instalador rodou mas o carimbo não avançou (ex.: install.sh do
      # projeto anterior a este release, sem .agents/VERSION na lista).
      # Chamar isso de ATUALIZADO esconderia exatamente o drift que o
      # comando existe para eliminar.
      add_report "PARCIAL" "$name" "$local_ver" "${new_ver:-?}" "instalador aplicado, mas VERSION não chegou a $REMOTE_VERSION — rode de novo (o install.sh do projeto foi renovado nesta rodada); log: $plog"
    fi
  else
    add_report "FALHA" "$name" "$local_ver" "-" "install.sh --update falhou — log: $plog"
  fi
done

# ── Relatório ───────────────────────────────────────────────────────────────
echo ""
echo -e "${CYAN}━━━ canuto update-all — relatório (remoto: $REMOTE_VERSION) ━━━${RESET}"
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
