---
type: decision
id: D-001
date: 2026-03-02
status: active
domain: stack
related-instincts: []
related-sessions: []
tags:
  - decision
  - stack
  - icons
---

# lucide-animated como biblioteca de ícones padrão

**Context:** Precisávamos definir uma biblioteca de ícones para o stack do framework.

**Decision:** Usar lucide-animated como padrão (via shadcn registry: `pnpm dlx shadcn add @lucide-animated/{icon-name}`), lucide-react como fallback para ícones estáticos.

**Reason:** lucide-animated oferece 379+ ícones animados com Motion sem custo extra — Motion já está aprovado no stack. Integra-se nativamente com shadcn/ui.

**Trade-offs:** Ícones são instalados individualmente (não como pacote npm global). Aceito — segue o padrão shadcn/ui de componentes copiados.
