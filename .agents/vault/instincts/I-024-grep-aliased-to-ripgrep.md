---
id: I-024
title: Bash `grep` está aliased pra ripgrep — sintaxe de regex difere
confidence: high
created: 2026-04-18
tags: [bash, grep, ripgrep, debugging]
---

# I-024 — `grep` no Bash deste ambiente é `rg`

## Pattern

Comandos como `grep "a\|b" file` no Bash retornam erro `parsing flag -E: grep config error: unknown encoding: a|b`. `grep` está aliased pra `rg` (ripgrep), que interpreta flags diferente de GNU/BSD grep.

## Evidence

**Sessão 2026-04-18:** durante validação de edits da FASE 2a, `grep -rln "gpt-5-codex\|o1-pro" .agents/` retornava vazio mesmo quando `grep -F "gpt-5-codex" arquivo.md` achava matches. Teste direto:

```bash
$ echo "test" | sed 's/test/OK/'  # funciona
$ grep -E "a|b" file  # erro: -E interpretado como --encoding
```

## How to apply

- Para regex alternation em Bash: usar `grep -F` (fixed-string) com múltiplos calls OU usar a ferramenta Grep do Claude Code (também ripgrep mas com sintaxe esperada)
- Para verificação de estado após edits em massa, **preferir a ferramenta Grep** sobre Bash grep — evita confusão de sintaxe
- `sed` BSD no macOS funciona normal (não está aliased)
