---
type: instinct
id: I-008
category: memory
confidence: high
applied: 0
source-session: "2026-03-23"
last-seen: 2026-03-23
status: active
promoted-to: ""
tags:
  - instinct
  - memory
  - vault
  - persistence
---

# Vault-native memory sobrevive ao context window

**Pattern:** Toda sessão termina com Maestro criando: nota de sessão, notas de pending tasks atualizadas, notas de decisions tomadas, nota de métricas, e events de audit. Instincts são extraídos e atomizados individualmente.

**Learning:** A principal falha em sistemas AI multi-sessão é perda de contexto entre sessões. O context window reseta, mas o vault não. Uma sessão bem documentada no vault vale o equivalente a 5.000-10.000 tokens de contexto recuperado na sessão seguinte — e é mais precisa que tentar reconstroir do histórico de git. O overhead de 2-3 minutos de session-end compensa centenas de tokens recuperados.

**Source:** [[sessions/2026-03-23]] — derivado de SPEC.md §5 (Memory & Session Persistence) + §5.5 (Token Economy)
