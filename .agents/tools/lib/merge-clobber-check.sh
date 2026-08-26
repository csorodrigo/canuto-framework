#!/usr/bin/env bash
# merge-clobber-check.sh — detecção de clobber de conteúdo em merge.
#
# Cenário que o freshness gate (behind>0) NÃO pega: branch "em dia" (contém a
# base) mas com resolução de conflito que descartou conteúdo do main (ex.:
# `git merge -s ours`, add/add resolvido pró-branch). Mecanismo dos incidentes
# #1980/#1985. Nota: após um `-s ours` o merge-base vira a própria base, então
# a detecção NÃO pode se apoiar no fork point — usa janela temporal.
#
# Técnica: merge simulado (git merge-tree --write-tree). Para cada arquivo em
# que o resultado do merge REMOVE linhas em relação à base HEAD, verifica se
# alguma dessas linhas foi ADICIONADA à base nos últimos N dias (default 14).
#
# ATRIBUIÇÃO (2026-07-21) — por que a interseção de linhas sozinha não bastava:
# o `anchor` é o commit MAIS ANTIGO da janela, então `base_added` acumula ~14
# dias de adições (3.826 linhas num arquivo quente). Contra esse palheiro,
# QUALQUER refactor sobre código recente cruza: linha modificada entra como
# removida+adicionada, e linha movida entra como removida. Na prática o gate
# acusava iteração sobre o trabalho recente da PRÓPRIA branch — inclusive o
# bump de cache-family que o `guard:cache-version` EXIGE, deixando os dois
# gates em contradição direta (PR #2207: 204 linhas acusadas em 14 arquivos,
# zero perda real, confirmado por três métodos independentes).
#
# Então, antes de acusar, cada linha da interseção é ATRIBUÍDA:
#   1. existe commit NÃO-merge em base..head que mexeu naquela linha naquele
#      arquivo? → edição deliberada, revisável no diff. Não é clobber.
#   2. a linha sobrevive na árvore mesclada? → foi MOVIDA (o `-S` do git conta
#      ocorrências, então mover não aparece como mudança). Não foi perdida.
#   3. nenhum dos dois → a linha evaporou na resolução do merge. É CLOBBER.
#
# É por linha, não por percentual: clobber PARCIAL continua detectável, que é
# o que a auditoria do #1980 pedia. O formato `-s ours` continua sendo pego —
# lá ninguém editou nada, o conteúdo some no merge, então cai direto no caso 3.
# Controle positivo usado na validação: commit sintético com a árvore do fork
# point e origin/main como 2º pai (= `merge -s ours`, behind=0, passa no
# freshness gate). Antes do patch: 70 arquivos acusados. Depois: 70.
#
# Uso: merge_clobber_check <base_ref> <head_ref> [dias]
# Retorno: 0 = limpo; 1 = clobber detectado (imprime arquivos + amostras);
#          2 = não foi possível checar (git antigo/conflito) — chamador decide.

# Fração de `base_added` que o merge removeria, a partir da qual o arquivo é
# acusado MESMO com toda linha atribuída. Fecha o caso "commit de 1 pai que
# reverte o arquivo para uma versão antiga": ali cada linha TEM um commit
# explícito (o próprio revert), então a atribuição sozinha deixava passar —
# o detector antigo pegava, e regressão de cobertura não é aceitável.
# Calibrado com medição, não com chute (2026-07-21): branch legítima com
# refactor pesado bate no máximo 9%; revert explícito de 6 commits do main dá
# 100%/100%/83%/50%/46%/37%/36%/31%. 25% fica ~3x acima do ruído observado.
MERGE_CLOBBER_BULK_PCT="${MERGE_CLOBBER_BULK_PCT:-25}"

merge_clobber_check() {
  local base="$1" head="$2" days="${3:-14}"
  local merged f anchor base_added merged_removed inter found=0
  local line who lost n_lost n_int n_add pct merged_blob reverted c

  merged=$(git merge-tree --write-tree "$base" "$head" 2>/dev/null) || return 2
  case "$merged" in *[!0-9a-f]*) return 2 ;; esac

  while IFS= read -r f; do
    [ -n "$f" ] || continue
    merged_removed=$(git diff "$base" "$merged" -- "$f" 2>/dev/null \
      | grep '^-' | grep -v '^---' | sed 's/^-//' | grep -E '[^[:space:]]{4,}' | sort -u)
    [ -n "$merged_removed" ] || continue
    # arquivo só importa se a base o tocou recentemente
    anchor=$(git rev-list --since="${days} days ago" --reverse "$base" -- "$f" 2>/dev/null | head -1)
    [ -n "$anchor" ] || continue
    if git rev-parse -q --verify "${anchor}^" >/dev/null 2>&1; then
      base_added=$(git diff "${anchor}^" "$base" -- "$f" 2>/dev/null \
        | grep '^+' | grep -v '^+++' | sed 's/^+//' | grep -E '[^[:space:]]{4,}' | sort -u)
    else
      base_added=$(git show "$base:$f" 2>/dev/null | grep -E '[^[:space:]]{4,}' | sort -u)
    fi
    [ -n "$base_added" ] || continue
    inter=$(comm -12 <(printf '%s\n' "$base_added") <(printf '%s\n' "$merged_removed"))
    [ -n "$inter" ] || continue

    # Atribuição linha a linha. `lost` guarda só as que ficaram sem explicação.
    lost=""; n_lost=0
    while IFS= read -r line; do
      [ -n "$line" ] || continue
      # (1) commit explícito da branch mexeu nesta linha?
      who=$(git log -S"$line" --no-merges --format=%h "$base".."$head" -- "$f" 2>/dev/null | head -1)
      [ -n "$who" ] && continue
      # (2) linha apenas movida? (-e porque a linha pode começar com '-')
      git grep -qF -e "$line" "$merged" 2>/dev/null && continue
      # (3) sem edição explícita e sem sobrevivente: sumiu no merge.
      n_lost=$((n_lost + 1))
      [ -z "$lost" ] && lost="$line"
      # 3 amostras bastam para o humano decidir; corta o custo no caso ruim.
      [ "$n_lost" -ge 3 ] && break
    done <<< "$inter"

    n_int=$(printf '%s\n' "$inter" | grep -c . )
    n_add=$(printf '%s\n' "$base_added" | grep -c . )
    pct=$(( n_int * 100 / (n_add > 0 ? n_add : 1) ))

    if [ "$n_lost" -gt 0 ]; then
      found=1
      echo "CLOBBER: $f — o merge removeria linha(s) adicionadas à base nos últimos ${days} dias,"
      echo "         sem commit explícito da branch que as tenha editado e sem sobrevivente na árvore:"
      printf '%s\n' "$lost" | head -3 | cut -c1-100 | sed 's/^/    | /'
    elif [ "$pct" -ge "$MERGE_CLOBBER_BULK_PCT" ]; then
      # Toda linha atribuída, mas o VOLUME denuncia: reverter um arquivo inteiro
      # também é "edição explícita" linha a linha. Aqui o que acusa é a fração.
      #
      # REFINO (2026-07-23, PRs #2207/#2243): fração alta sozinha acusava
      # refactor legítimo de arquivo quente (branch reescreve trecho que a base
      # também tocou na janela — 30% medido em refactor real, acima do piso).
      # Discriminador: assinatura de REVERT. Reverter restaura um blob
      # HISTÓRICO do arquivo; refactor produz conteúdo novo. Só acusa por
      # volume se o resultado do merge for idêntico a uma versão passada do
      # arquivo na base (ou se o arquivo sumir por inteiro). Revert parcial com
      # tweak escapa da igualdade de blob, mas as linhas perdidas que o tweak
      # não explica continuam caindo no caso n_lost>0 acima.
      merged_blob=$(git rev-parse -q --verify "$merged:$f" 2>/dev/null || true)
      reverted=0
      if [ -z "$merged_blob" ]; then
        # arquivo deletado no merge: deleção em massa de conteúdo recente segue acusada
        reverted=1
      else
        while IFS= read -r c; do
          if [ "$(git rev-parse -q --verify "$c:$f" 2>/dev/null)" = "$merged_blob" ]; then
            reverted=1
            break
          fi
        done < <(git rev-list "$base" -- "$f" 2>/dev/null | head -500)
      fi
      if [ "$reverted" = 1 ]; then
        found=1
        echo "CLOBBER (volume): $f — o merge removeria ${pct}% do que a base adicionou nos"
        echo "         últimos ${days} dias (${n_int} de ${n_add} linhas), acima do piso de ${MERGE_CLOBBER_BULK_PCT}%,"
        echo "         e o resultado restaura uma versão histórica do arquivo (assinatura de revert)."
        printf '%s\n' "$inter" | head -3 | cut -c1-100 | sed 's/^/    | /'
      fi
    fi
  done < <(git diff --name-only "$base" "$merged" 2>/dev/null)

  [ "$found" = 1 ] && return 1
  return 0
}
