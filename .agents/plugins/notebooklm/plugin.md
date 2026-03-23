---
name: notebooklm
version: 0.1.0
description: Programmatic access to Google NotebookLM — research, audio overviews, and artifact generation
author: canuto-framework
requires:
  - python3
compatible: ">=1.6.0"
---

# NotebookLM Plugin

Integrates Google NotebookLM into Canuto sessions via the `notebooklm-py` unofficial CLI. Enables AI-powered web research, podcast generation from session notes, and structured artifact export (reports, mind maps, slide decks, quizzes).

## Skills Provided

| Skill | Trigger | Description |
|-------|---------|-------------|
| `notebooklm` | `/notebooklm` | Full NotebookLM operations: research, audio, artifacts, chat |

## Setup

1. Install the CLI:
   ```bash
   pip install notebooklm-py
   notebooklm login   # Google OAuth via browser
   notebooklm status  # confirm auth
   ```

2. Copy this plugin to `.agents/plugins/notebooklm/` in your project.

3. Optionally pin a default notebook in CLAUDE.md:
   ```markdown
   ## Plugins
   - notebooklm:
     default_notebook_id: "abc123"  # from `notebooklm list --json`
   ```

## When Maestro Should Load This Plugin

- User mentions "NotebookLM", "podcast de sessão", "audio overview"
- User wants automated web research / source discovery
- User wants deliverable export: report, mind map, slide deck, quiz, flashcards
- User wants to ask questions over a large corpus of documents (RAG)

## Risks

- **API instável**: usa RPC endpoints não-oficiais do Google — pode quebrar sem aviso. Monitorar [releases](https://github.com/teng-lin/notebooklm-py/releases).
- **Auth expirada**: reautenticar com `notebooklm login` se comandos retornarem 401/403.
- **Privacidade**: todo conteúdo vai para servidores Google. Não usar com dados sensíveis ou proprietários.
- **Quotas**: NotebookLM free tem limites de uso; heavy use pode requerer Google One AI Premium.

## Notes

Este é um plugin **opt-in**. Não altera o comportamento padrão do framework. Invoke explicitamente via `/notebooklm` ou quando Maestro identificar os gatilhos acima.
