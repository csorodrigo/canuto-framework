#!/usr/bin/env bash
# post-compact-reread.sh — SessionStart(matcher: compact).
# Após compactação o estado "arquivos já lidos" se perde e o modelo tenta Edit
# sem Read (352 falhas de sequenciamento na auditoria 2026-07-17). Injeta como
# contexto a lista dos últimos arquivos editados para Read dirigido.
set -uo pipefail
IN=$(cat 2>/dev/null || true)
command -v jq >/dev/null 2>&1 || exit 0
TP=$(printf '%s' "$IN" | jq -r '.transcript_path // empty' 2>/dev/null) || TP=""
[ -n "$TP" ] && [ -f "$TP" ] || exit 0

# Últimos ~3MB do transcript; 1ª linha pode estar cortada → fromjson? ignora.
files=$(tail -c 3000000 "$TP" 2>/dev/null \
  | jq -rR 'fromjson? | select(.type=="assistant") | .message.content[]? | select(.type=="tool_use") | select(.name=="Edit" or .name=="Write" or .name=="MultiEdit" or .name=="NotebookEdit") | .input.file_path // empty' 2>/dev/null \
  | awk 'NF' | awk '!seen[$0]++' | tail -8) || files=""
[ -n "$files" ] || exit 0

echo "Pós-compactação: o estado de leitura foi perdido. Antes do primeiro Edit em qualquer arquivo abaixo, faça Read nele primeiro (evita o erro de editar sem ler):"
printf '%s\n' "$files" | sed 's/^/  - /'
exit 0
