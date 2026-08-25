---
type: decision
id: D-005
date: 2026-03-23
status: active
domain: memory
related-instincts: [I-008]
related-sessions: []
tags:
  - decision
  - memory
  - obsidian
  - persistence
---

# Vault Obsidian global como memória persistente

**Context:** O context window de LLMs é finito e resetado a cada sessão. Precisávamos de um mecanismo de memória persistente que: sobrevivesse entre sessões, suportasse queries ricas, e fosse legível por humanos.

**Decision:** Memória nativa em Obsidian vault global em `~/.canuto/vault/`. Cada projeto tem seu escopo em `projects/{slug}/`. Tipos atomizados: sessions, decisions, instincts, pending, audit, metrics, design. Acessado via MCP server (`obsidian-mcp-server`).

**Reason:** Obsidian é Markdown nativo (sem lock-in), suporta queries via Bases (frontmatter YAML), tem wikilinks para cross-referência, e funciona offline. O MCP server permite que o Claude leia/escreva o vault programaticamente. Atomização por tipo permite busca seletiva (salva tokens: carrega só o que é relevante).

**Trade-offs:** Requer setup manual (Obsidian instalado + plugin Local REST API + MCP configurado). Aceito: é setup único por máquina, e o ganho em qualidade de contexto supera o overhead inicial.

**Related:** [[instincts/I-008-vault-memory-sobrevive-context-window]]
