---
type: decision
id: D-009
date: 2026-03-23
status: active
domain: stack
related-instincts: []
related-sessions: []
tags:
  - decision
  - stack
  - consistency
  - library-drift
---

# Stack lock via .agents/stack.md para evitar library drift

**Context:** Em projetos com múltiplas sessões de AI, diferentes personas podem propor bibliotecas diferentes para o mesmo problema (ex.: axios vs fetch, date-fns vs dayjs), gerando inconsistência ao longo do tempo.

**Decision:** Cada projeto mantém um `.agents/stack.md` com as bibliotecas aprovadas por categoria. O Architect DEVE consultar stack.md antes de propor qualquer dependência. Se a biblioteca necessária não está em stack.md, o Architect pede aprovação ao usuário antes de prosseguir.

**Reason:** Consistência de stack reduz bundle size, simplifica onboarding, e evita conflitos de versão. A aprovação explícita mantém o usuário no controle sem bloquear progress.

**Trade-offs:** Requer manutenção ativa do stack.md conforme o projeto evolui. Aceito — é trabalho de curadoria, não de manutenção contínua. O Architect atualiza stack.md quando uma nova biblioteca é aprovada.

**Related:** [[decisions/D-003-github-template-distribution]]
