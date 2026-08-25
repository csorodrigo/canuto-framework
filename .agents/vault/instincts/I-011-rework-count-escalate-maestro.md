---
type: instinct
id: I-011
category: convergence
confidence: high
applied: 0
source-session: "2026-03-23"
last-seen: 2026-03-23
status: active
promoted-to: ""
tags:
  - instinct
  - rework
  - escalation
  - maestro
  - convergence-detection
---

# rework_count > 2 → escalate to Maestro

**Pattern:** Quando o ciclo Coder → Tester → Debugger → Coder acontece mais de 2 vezes para o mesmo problema, Maestro interrompe o loop e reavalia: re-plan com Architect, resolver inline, ou perguntar ao usuário.

**Learning:** Loops de rework convergem para a solução errada com muita frequência. Após 2 iterações sem convergência, o problema geralmente não é implementação — é o plano original que está errado, ou há um constraint não descoberto. Adicionar uma 3ª iteração ao mesmo loop é, estatisticamente, mais provável de gerar uma solução frágil do que uma solução correta. Escalação para Maestro força um step back.

**Source:** [[sessions/2026-03-23]] — derivado de SPEC.md §11.8 (Convergence Detection) + skill convergence-detection.md
