---
type: instinct
id: I-022
category: onboarding
confidence: medium
applied: 0
source-session: "2026-03-25"
last-seen: 2026-03-25
status: active
promoted-to: ""
tags:
  - instinct
  - install
  - migracao
---

# Migração vs fresh install — confusão recorrente

**Pattern:** Quando um usuário relata erro ao rodar `--migrate` em um projeto já migrado.

**Learning:** O flag `--migrate` é específico para conversão de formato (v1.5 flat → v1.6+ Obsidian). Usuários confundem com "atualizar" e tentam usar em projetos que já estão no formato correto, resultando em output aparentemente bem-sucedido mas sem efeito real. Fresh install (projeto sem `.agents/`) = `curl -fsSL ... | bash` sem flags. Atualização de projeto existente = também sem flags (o script detecta e atualiza).

**Source:** [[sessions/2026-03-25]]
