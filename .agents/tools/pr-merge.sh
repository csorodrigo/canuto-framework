#!/usr/bin/env bash
# pr-merge.sh <pr-number> [--repo owner/repo] [--method squash|merge|rebase] [--sha expected-head] [--keep-branch]
#
# Merge a PR via the GitHub API without touching any local branch.
# canuto:pinned-sha-merge:v1 — --sha is forwarded atomically to the merge API.
# Rationale (session-error audit 2026-07-05): `gh pr merge` updates the local
# `main` checkout, which fails with "'main' is already used by worktree at ..."
# in multi-worktree Conductor setups — 12 sessions hit this in one week.
set -euo pipefail

PR="${1:?usage: pr-merge.sh <pr-number> [--repo owner/repo] [--method squash|merge|rebase] [--sha expected-head] [--keep-branch]}"
shift
case "$PR" in ''|*[!0-9]*) echo "pr-number must be numeric" >&2; exit 64 ;; esac
REPO=""
METHOD="squash"
DELETE_BRANCH=1
EXPECTED_SHA=""
while [ $# -gt 0 ]; do
  case "$1" in
    --repo) [ $# -ge 2 ] || { echo "--repo requires a value" >&2; exit 64; }; REPO="$2"; shift 2 ;;
    --method) [ $# -ge 2 ] || { echo "--method requires a value" >&2; exit 64; }; METHOD="$2"; shift 2 ;;
    --sha) [ $# -ge 2 ] || { echo "--sha requires a value" >&2; exit 64; }; EXPECTED_SHA="$2"; shift 2 ;;
    --keep-branch) DELETE_BRANCH=0; shift ;;
    *) echo "unknown arg: $1" >&2; exit 64 ;;
  esac
done

if [ -n "$EXPECTED_SHA" ] && ! [[ "$EXPECTED_SHA" =~ ^[0-9a-f]{40}$ ]]; then
  echo "--sha must be a full lowercase 40-character commit SHA" >&2
  exit 64
fi

[ -z "$REPO" ] && REPO=$(gh repo view --json nameWithOwner -q .nameWithOwner)
[[ "$REPO" =~ ^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$ ]] || { echo "--repo must be owner/repo" >&2; exit 64; }
case "$METHOD" in squash|merge|rebase) ;; *) echo "--method must be squash, merge or rebase" >&2; exit 64 ;; esac
REPO_ROOT="$(git rev-parse --show-toplevel 2>/dev/null)" || { echo "pr-merge.sh must run inside the target repository" >&2; exit 64; }
ORIGIN_URL="$(git -C "$REPO_ROOT" remote get-url origin 2>/dev/null)" || { echo "target repository has no origin remote" >&2; exit 64; }
ORIGIN_REPO="$(env -u GH_REPO gh repo view "$ORIGIN_URL" --json nameWithOwner -q .nameWithOwner)"
[ "$ORIGIN_REPO" = "$REPO" ] || { echo "target repo $REPO differs from origin repo $ORIGIN_REPO" >&2; exit 64; }

# Serializa todos os merges feitos por este helper neste host. O endpoint de
# merge aceita precondicao apenas para o head, nao para a base; por isso o lock
# cobre o snapshot, os gates e o PUT. Merge manual/remoto fora deste helper
# continua sendo o bypass operacional explicitamente fora da garantia local.
MERGE_LOCK_OWNER="${REPO%%/*}"
MERGE_LOCK_REPO="${REPO#*/}"
MERGE_LOCK_ROOT="$HOME/.claude/locks/pr-merge/$MERGE_LOCK_OWNER"
MERGE_LOCK_FILE="$MERGE_LOCK_ROOT/$MERGE_LOCK_REPO.lock"
mkdir -p "$MERGE_LOCK_ROOT"
command -v flock >/dev/null 2>&1 || { echo "pr-merge.sh requires flock for merge serialization" >&2; exit 69; }
exec 9>"$MERGE_LOCK_FILE"
if ! flock -n 9; then
  echo "PR #$PR: outro merge deste repositorio esta em andamento neste host" >&2
  exit 75
fi
CONTENT_HEAD_REF=""
CONTENT_BASE_REF=""
cleanup_merge_state() {
  [ -z "$CONTENT_HEAD_REF" ] || git update-ref -d "$CONTENT_HEAD_REF" 2>/dev/null || true
  [ -z "$CONTENT_BASE_REF" ] || git update-ref -d "$CONTENT_BASE_REF" 2>/dev/null || true
}
handle_merge_int() { cleanup_merge_state; trap - EXIT; exit 130; }
handle_merge_term() { cleanup_merge_state; trap - EXIT; exit 143; }
trap cleanup_merge_state EXIT
trap handle_merge_int INT
trap handle_merge_term TERM

info=$(gh pr view "$PR" --repo "$REPO" --json state,mergeable,headRefName,headRefOid,isCrossRepository,title,baseRefName,baseRefOid)
state=$(jq -r .state <<<"$info")
mergeable=$(jq -r .mergeable <<<"$info")
head_ref=$(jq -r .headRefName <<<"$info")
head_oid=$(jq -r .headRefOid <<<"$info")
cross=$(jq -r .isCrossRepository <<<"$info")
base_ref=$(jq -r .baseRefName <<<"$info")
base_oid=$(jq -r .baseRefOid <<<"$info")
authorized_head_oid="$head_oid"

if ! [[ "$authorized_head_oid" =~ ^[0-9a-f]{40}$ ]] || ! [[ "$base_oid" =~ ^[0-9a-f]{40}$ ]]; then
  echo "PR #$PR returned invalid head/base OIDs" >&2
  exit 7
fi

if [ "$state" != "OPEN" ]; then
  echo "PR #$PR is $state, nothing to merge." >&2
  exit 1
fi
if [ "$mergeable" = "CONFLICTING" ]; then
  echo "PR #$PR has conflicts with base — resolve on the PR branch first (never on local main)." >&2
  exit 1
fi
if [ -n "$EXPECTED_SHA" ] && [ "$head_oid" != "$EXPECTED_SHA" ]; then
  echo "PR #$PR head moved: expected $EXPECTED_SHA, observed $head_oid." >&2
  exit 7
fi

# Autoridade local opt-in do projeto. A presenca do hook e decidida pela base
# confiavel, e os bytes executados tambem vem da base; o worktree apontado por
# CLAUDE_PROJECT_DIR permanece pinado no head candidato.
run_project_merge_authority() (
  set -euo pipefail
  local hook_path=".agents/hooks/require-tests-for-pr.sh"
  local temp_root authority_repo worktree hook_probe hook_probe_rc=0
  local head_check_ref="refs/pr-merge-authority/$PR-$$-head"
  temp_root="$(mktemp -d "${TMPDIR:-/tmp}/pr-merge-hook.XXXXXX")"
  authority_repo=""
  worktree="$temp_root/worktree"

  cleanup_authority() {
    if [ -n "$authority_repo" ]; then
      git -C "$authority_repo" worktree remove --force "$worktree" >/dev/null 2>&1 || true
      git -C "$authority_repo" update-ref -d "$head_check_ref" >/dev/null 2>&1 || true
    fi
    rm -rf "$temp_root"
  }
  handle_authority_int() { cleanup_authority; trap - EXIT; exit 130; }
  handle_authority_term() { cleanup_authority; trap - EXIT; exit 143; }
  trap cleanup_authority EXIT
  trap handle_authority_int INT
  trap handle_authority_term TERM

  hook_probe="$(gh api -i -H 'Accept: application/vnd.github+json' \
    "repos/$REPO/contents/$hook_path?ref=$base_oid" 2>&1)" || hook_probe_rc=$?
  if [ "$hook_probe_rc" -ne 0 ]; then
    if printf '%s' "$hook_probe" | grep -Eqi '(^|[[:space:]])404([[:space:]]|$)|Not Found'; then
      exit 0
    fi
    echo "PR #$PR: nao foi possivel determinar o opt-in da autoridade local" >&2
    exit 2
  fi
  authority_repo="$REPO_ROOT"

  git -C "$authority_repo" fetch -q origin \
    "+refs/pull/$PR/head:$head_check_ref" \
    "+refs/heads/$base_ref:refs/remotes/origin/$base_ref"
  local fetched_sha
  fetched_sha="$(git -C "$authority_repo" rev-parse "$head_check_ref")"
  if [ "$fetched_sha" != "$head_oid" ]; then
    echo "PR #$PR authority fetch mismatch: API=$head_oid fetched=$fetched_sha" >&2
    exit 7
  fi
  if [ "$(git -C "$authority_repo" rev-parse "refs/remotes/origin/$base_ref")" != "$base_oid" ]; then
    echo "PR #$PR authority base moved from $base_oid" >&2
    exit 7
  fi
  git -C "$authority_repo" worktree add --detach "$worktree" "$head_check_ref" >/dev/null
  # O hook de autoridade roda tooling node (change-validation + gate semantico do #805) e o
  # worktree descartavel nasce SEM node_modules: o validador morria em silencio (stderr
  # engolido) e o HOLD saia como "sem bump semantico valido" para QUALQUER PR — visto em
  # 25/08/2026 com #806 e #807, ambos com validador verde quando rodado de um clone completo.
  if [ -d "$authority_repo/node_modules" ] && [ ! -e "$worktree/node_modules" ]; then
    ln -s "$authority_repo/node_modules" "$worktree/node_modules"
  fi
  git -C "$authority_repo" show "$base_oid:$hook_path" > "$temp_root/require-tests-for-pr.sh"
  local hook_rc=0
  env -u CANUTO_GATE_VIA CLAUDE_PROJECT_DIR="$worktree" \
    bash "$temp_root/require-tests-for-pr.sh" || hook_rc=$?
  if [ "$hook_rc" -ne 0 ]; then
    echo "PR #$PR: HOLD da autoridade local em $hook_path para $head_oid" >&2
    exit "$hook_rc"
  fi
  echo "project-authority: hook verde para $head_oid."
)

# Anti-clobber gate (lucrando-ai, 2026-07-14): squash-merge de branch STALE ja
# reverteu silenciosamente arquivos que outros PRs tinham avancado (2x: #1985
# brand-availability, #1980 local-first-pull-service — quebrou onboarding em
# prod). Branch protection "up to date" e inviavel (repo privado sem Pro),
# entao o unico caminho de merge (este script) exige branch em dia com a base.
# Override deliberado: PR_MERGE_ALLOW_BEHIND=1 (so apos conferir que o diff do
# PR nao toca arquivo avancado na base depois do fork point).
if [ "${PR_MERGE_ALLOW_BEHIND:-0}" != "1" ]; then
  base_ref="${base_ref:-$(gh pr view "$PR" --repo "$REPO" --json baseRefName -q .baseRefName)}"
  # O SHA observado funciona tambem para PRs de fork; nome de branch nao.
  head_enc="$head_oid"
  base_enc="$base_oid"
  behind=$(gh api "repos/$REPO/compare/$head_enc...$base_enc" --jq .ahead_by 2>/dev/null) || {
    echo "PR #$PR: nao consegui medir atraso da branch vs $base_ref" >&2
    exit 5
  }
  if [ -z "$behind" ]; then
    echo "PR #$PR: resposta vazia ao medir atraso vs $base_ref" >&2
    exit 5
  elif [ "$behind" -gt 0 ]; then
    echo "PR #$PR: branch $head_ref esta $behind commit(s) ATRAS de $base_ref." >&2
    echo "Merge de branch stale ja clobrou main 2x (#1980/#1985). Atualize a branch:" >&2
    echo "  git fetch origin && git merge origin/$base_ref  (ou rebase) e rode o build-gate de novo." >&2
    echo "Override deliberado (apos conferir o diff): PR_MERGE_ALLOW_BEHIND=1" >&2
    exit 5
  else
    echo "anti-clobber: branch em dia com $base_ref (behind=0)."
  fi
fi

# Content gate (auditoria 2026-07-17): o freshness gate acima não pega branch
# "em dia" (behind=0) cuja resolução de conflito descartou conteúdo da base
# (merge -s ours / add-add resolvido pró-branch — mecanismo do #1980/#1985).
# Simula o merge e bloqueia se o resultado desfaz linhas que a base adicionou
# depois do fork. Ausencia da biblioteca ou falha de simulacao bloqueiam o merge.
# Override deliberado: PR_MERGE_ALLOW_CONTENT=1 (só após inspecionar o diff).
if [ "${PR_MERGE_ALLOW_CONTENT:-0}" != "1" ]; then
  CLOBBER_LIB="$HOME/.claude/scripts/lib/merge-clobber-check.sh"
  if [ ! -f "$CLOBBER_LIB" ]; then
    echo "content-gate: biblioteca ausente em $CLOBBER_LIB" >&2
    exit 6
  fi
  if ! git rev-parse --git-dir >/dev/null 2>&1; then
    echo "content-gate: cwd nao pertence a um repositorio Git" >&2
    exit 6
  fi
  # shellcheck source=/dev/null
  . "$CLOBBER_LIB"
    base_ref="${base_ref:-$(gh pr view "$PR" --repo "$REPO" --json baseRefName -q .baseRefName)}"
    content_head_ref="refs/pr-merge-check/$PR-$$-head"
    content_base_ref="refs/pr-merge-check/$PR-$$-base"
    CONTENT_HEAD_REF="$content_head_ref"
    CONTENT_BASE_REF="$content_base_ref"
    cleanup_content_refs() {
      git update-ref -d "$content_head_ref" 2>/dev/null || true
      git update-ref -d "$content_base_ref" 2>/dev/null || true
    }
    if git fetch -q origin "+refs/pull/$PR/head:$content_head_ref" \
                          "+refs/heads/$base_ref:$content_base_ref" 2>/dev/null; then
      [ "$(git rev-parse "$content_head_ref")" = "$head_oid" ] || {
        echo "PR #$PR: content gate recebeu head diferente do OID observado" >&2
        exit 6
      }
      [ "$(git rev-parse "$content_base_ref")" = "$base_oid" ] || {
        echo "PR #$PR: content gate recebeu base diferente do OID observado" >&2
        exit 6
      }
      # `|| clobber_rc=$?`: sem isso, `set -e` mata o script no rc!=0 da command
      # substitution ANTES do tratamento — era exit 1 mudo em vez do exit 6 com
      # diagnóstico (reincidiu 2x em 2026-07-19, sessões #56 e #57).
      clobber_rc=0
      clobber_out=$(merge_clobber_check "$content_base_ref" "$content_head_ref") || clobber_rc=$?
      cleanup_content_refs
      CONTENT_HEAD_REF=""
      CONTENT_BASE_REF=""
      if [ "$clobber_rc" = 1 ]; then
        echo "PR #$PR: CONTENT GATE — o merge desfaria avanço recente da base ($base_ref):" >&2
        printf '%s\n' "$clobber_out" >&2
        echo "Se o revert é INTENCIONAL, inspecione o diff e use PR_MERGE_ALLOW_CONTENT=1." >&2
        exit 6
      elif [ "$clobber_rc" = 2 ]; then
        echo "content-gate: nao foi possivel simular o merge" >&2
        exit 6
      else
        echo "content-gate: merge simulado nao desfaz conteudo da base."
      fi
    else
      echo "content-gate: fetch dos refs falhou" >&2
      exit 6
    fi
fi

# Executa depois de freshness/content e antes de qualquer build receipt ou PUT.
authority_rc=0
run_project_merge_authority || authority_rc=$?
if [ "$authority_rc" -ne 0 ]; then
  exit "$authority_rc"
fi

# Build gate (lucrando-ai, 2026-07-10): Actions are disabled in that repo (no
# plan), so PRs get no CI. Require a READY receipt from scripts/ops/
# pr-build-gate.mjs (preview deploy on Vercel = the exact prod build incl.
# typecheck) for the PR head sha. Receipts live in <git-common-dir>/
# canuto-receipts/. Repos without a canuto-receipts dir are unaffected.
if [ "${PR_MERGE_SKIP_BUILD_GATE:-0}" != "1" ]; then
  common=$(git rev-parse --git-common-dir 2>/dev/null || true)
  if [ -n "$common" ] && [ -d "$common/canuto-receipts" ]; then
    receipt="$common/canuto-receipts/build-$authorized_head_oid.json"
    state=""
    [ -f "$receipt" ] && state=$(jq -r '.state // ""' "$receipt" 2>/dev/null)
    if [ "$state" != "READY" ]; then
      echo "PR #$PR: sem receipt de build READY para o head $authorized_head_oid (${receipt}: ${state:-ausente})." >&2
      echo "Rode no worktree da branch (tree limpa): node scripts/ops/pr-build-gate.mjs" >&2
      echo "Motivo: main ja quebrou 2x por erro de TS que so aparece no build; sem Actions neste repo." >&2
      echo "Override deliberado: PR_MERGE_SKIP_BUILD_GATE=1" >&2
      exit 3
    fi
    echo "build-gate: receipt READY para $authorized_head_oid."
  fi
fi

final_info=$(gh pr view "$PR" --repo "$REPO" --json state,headRefOid,baseRefOid)
final_state=$(jq -r .state <<<"$final_info")
final_head_oid=$(jq -r .headRefOid <<<"$final_info")
final_base_oid=$(jq -r .baseRefOid <<<"$final_info")
if [ "$final_state" != "OPEN" ] || [ "$final_head_oid" != "$authorized_head_oid" ] || [ "$final_base_oid" != "$base_oid" ]; then
  echo "PR #$PR moved after validation: state=$final_state head=$final_head_oid base=$final_base_oid" >&2
  exit 7
fi

merge_response=$(gh api -X PUT "repos/$REPO/pulls/$PR/merge" -f merge_method="$METHOD" -f sha="$authorized_head_oid")
if ! jq -e '.merged == true' >/dev/null 2>&1 <<<"$merge_response"; then
  echo "PR #$PR merge API refused the merge: $(jq -r '.message // "unknown response"' <<<"$merge_response")" >&2
  exit 7
fi
jq -r '"merged: \(.merged) sha: \(.sha)"' <<<"$merge_response"

if [ "$DELETE_BRANCH" = "1" ] && [ "$cross" != "true" ]; then
  git -C "$REPO_ROOT" push --porcelain \
    --force-with-lease="refs/heads/$head_ref:$authorized_head_oid" \
    origin --delete "$head_ref" >/dev/null 2>&1 \
    && echo "deleted remote branch $head_ref" \
    || echo "remote branch $head_ref not deleted: ref moved, protected, or already gone"
fi
echo "PR #$PR merged via API — no local branch was touched. Update worktrees with: git fetch origin"
