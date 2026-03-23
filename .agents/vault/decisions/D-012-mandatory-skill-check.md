---
type: decision
id: D-012
date: 2026-03-23
status: active
domain: process
related-instincts: [I-014]
related-sessions: []
tags:
  - decision
  - process
  - skills
  - maestro
  - enforcement
---

# 1% Rule — Skill Check obrigatório antes de qualquer roteamento

**Context:** O framework tem 48+ skills documentados, mas não havia mecanismo que forçasse os agentes a verificar se um skill aplicável existia antes de agir. Os skills eram consultados quando o agente se lembrava ou quando explicitamente instruído, mas não de forma sistemática.

**Decision:** Adicionar "Skill Check" como Step 0 no playbook do Maestro, antes do Task Sizing. Criar o skill `skill-check-protocol` com a **1% Rule**: se há 1% de chance de um skill se aplicar, ele DEVE ser lido antes de prosseguir. O skill documenta racionalizações comuns para pular o check e por que estão erradas.

**Reason:** Skills sem enforcement são documentação morta. A 1% Rule, inspirada em `obra/superpowers`, muda o default de "lembro se precisar" para "verifico sempre". O custo de ler um skill (segundos) é menor que o custo de violar uma guardrail que ele protege (rework, bugs, inconsistências arquiteturais).

**Trade-offs:** Adiciona uma etapa em todo roteamento. Para tasks XS onde nenhum skill se aplica, o overhead é trivial (decisão negativa rápida). Para tasks M/L com skills aplicáveis, o benefício supera significativamente o custo.

**Related:** [[instincts/I-014-mandatory-skill-check]]
