#!/usr/bin/env bash
# env-bitwarden-sync.sh — sync .env files between a project and Bitwarden vault.
#
# Uses secure notes (base64-encoded content). Attachments are Premium-only on
# the Free plan; this workflow stays Free-tier compatible and covers .env sizes
# up to ~10 KB of plaintext.
#
# ────────────────────────────────────────────────────────────────────────────
# One-time setup:
#   brew install bitwarden-cli        # installs `bw`
#   bw login                          # interactive, uses email + password
#   eval "$(bw unlock | grep 'export BW_SESSION')"
#
# Keep `BW_SESSION` private — never commit it, never echo it in logs.
# If you suspect it leaked: `bw lock && bw unlock` to rotate.
#
# ────────────────────────────────────────────────────────────────────────────
# Usage:
#   env-bitwarden-sync.sh push <project-slug> [path-to-env]   # default: ./.env
#   env-bitwarden-sync.sh pull <project-slug> [path-to-env]   # default: ./.env
#   env-bitwarden-sync.sh list                                # show canuto-env-* items
#
# The item name in Bitwarden is "canuto-env-<project-slug>".

set -o pipefail

die() { printf 'error: %s\n' "$1" >&2; exit 1; }

subcmd="${1:-}"
slug="${2:-}"
envfile="${3:-./.env}"

[ -z "$subcmd" ] && die "missing subcommand. use: push|pull|list"
command -v bw >/dev/null 2>&1 || die "bw (bitwarden-cli) not installed. brew install bitwarden-cli"
command -v jq >/dev/null 2>&1 || die "jq required"

if [ -z "${BW_SESSION:-}" ]; then
  die "BW_SESSION not exported. Run: eval \"\$(bw unlock | grep 'export BW_SESSION')\""
fi

# bw reads BW_SESSION from the environment automatically; never pass via argv
# (would leak the token through `ps`/process listings).
export BW_SESSION

case "$subcmd" in
  list)
    bw list items 2>/dev/null \
      | jq -r '.[] | select(.name | startswith("canuto-env-")) | "\(.name)\t\(.revisionDate)"'
    ;;

  push)
    [ -z "$slug" ] && die "missing project-slug. usage: push <slug> [envfile]"
    [ ! -f "$envfile" ] && die "file not found: $envfile"
    name="canuto-env-$slug"

    bw sync >/dev/null 2>&1

    content=$(base64 < "$envfile" | tr -d '\n')

    item_id=$(bw list items --search "$name" 2>/dev/null \
      | jq -r --arg n "$name" '.[] | select(.name == $n) | .id' | head -1)

    if [ -n "$item_id" ]; then
      updated=$(bw get item "$item_id" 2>/dev/null \
        | jq --arg c "$content" '.notes = $c')
      echo "$updated" | bw encode | bw edit item "$item_id" >/dev/null \
        && printf 'updated: %s\n' "$name" \
        || die "failed to update $name"
    else
      tmpl=$(bw get template item)
      created=$(echo "$tmpl" \
        | jq --arg n "$name" --arg c "$content" '.type = 2 | .name = $n | .notes = $c | .secureNote.type = 0 | .login = null | .card = null | .identity = null | .folderId = null')
      echo "$created" | bw encode | bw create item >/dev/null \
        && printf 'created: %s\n' "$name" \
        || die "failed to create $name"
    fi
    ;;

  pull)
    [ -z "$slug" ] && die "missing project-slug. usage: pull <slug> [envfile]"
    name="canuto-env-$slug"

    bw sync >/dev/null 2>&1

    notes=$(bw get notes "$name" 2>/dev/null)
    [ -z "$notes" ] && die "item not found: $name (run 'list' to see available)"

    # Decode to a temp file first; only overwrite $envfile on success (atomic).
    tmp=$(mktemp "${envfile}.XXXXXX") || die "failed to create temp file"
    trap 'rm -f "$tmp"' EXIT

    if ! printf '%s' "$notes" | base64 -d > "$tmp" 2>/dev/null; then
      die "failed to decode base64 payload for $name"
    fi
    [ ! -s "$tmp" ] && die "decoded payload is empty for $name"

    if [ -f "$envfile" ]; then
      ts=$(date +%s)
      cp "$envfile" "${envfile}.bak.${ts}" && printf 'backup: %s.bak.%s\n' "$envfile" "$ts"
    fi

    mv "$tmp" "$envfile" \
      && printf 'pulled: %s → %s (%d bytes)\n' "$name" "$envfile" "$(wc -c < "$envfile" | tr -d ' ')" \
      || die "failed to move decoded payload into $envfile"
    trap - EXIT
    ;;

  *)
    die "unknown subcommand: $subcmd (use push|pull|list)"
    ;;
esac
