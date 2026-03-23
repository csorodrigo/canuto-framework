---
type: decision
id: D-004
date: 2026-03-23
status: active
domain: personas
related-instincts: [I-009]
related-sessions: []
tags:
  - decision
  - personas
  - providers
---

# Tier system de personas (Claude tier-1, mixed tier-2)

**Context:** Diferentes personas têm diferentes requisitos de qualidade e custo. Maestro e Architect precisam de raciocínio de alta qualidade; Coder e Tester podem usar modelos mais baratos sem perda significativa.

**Decision:** Personas são classificadas em 2 tiers. Tier-1 (Maestro, Architect, Contextualizer): sempre Claude. Tier-2 (Coder, Tester, Debugger, Reviewer): pode usar Claude, Codex, ou GLM conforme config em CLAUDE.md.

**Reason:** Concentra custo onde o impacto é maior (planejamento e orquestração). Permite economia de 30-50% em projetos intensivos de código sem comprometer a qualidade das decisões arquiteturais.

**Trade-offs:** Reviewer deve usar provider diferente do Coder para garantir perspectiva fresca — isso cria uma constraint de configuração. Aceito: o ganho em qualidade de review supera a complexidade.

**Related:** [[instincts/I-009-reviewer-diferente-do-coder]]
