---
type: decision
id: D-003
date: 2026-03-23
status: active
domain: distribution
related-instincts: []
related-sessions: []
tags:
  - decision
  - distribution
  - architecture
---

# Distribuição como GitHub Template repo

**Context:** Precisávamos definir como o framework seria distribuído para novos projetos. As alternativas eram: npm package, git submodule, git subtree, ou GitHub template.

**Decision:** Distribuição via GitHub template repo. O framework é copiado integralmente (snapshot) para cada projeto. Updates são aplicados manualmente.

**Reason:** Template repo é zero-dependency — não exige npm, não polui package.json, não cria coupling com versão remota. Cada projeto tem sua cópia isolada, o que garante estabilidade. A estrutura `.agents/` é gitignore-friendly e não conflita com nenhum stack.

**Trade-offs:** Updates não são automáticos — o usuário precisa manualmente aplicar mudanças do template central. Aceito: o framework é estável e updates são raros; autonomia do projeto > conveniência de sync automático.

**Related:** [[decisions/D-009-stack-lock]]
