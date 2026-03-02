# Decisions Log

> Append-only log of architectural and business decisions made across sessions.
> Each entry records WHAT was decided, WHY, and WHEN.
> This file saves tokens by preventing re-discussion of settled topics.

---

<!-- Append new decisions below this line. Do not delete previous entries. -->

## 2026-03-02 — lucide-animated como biblioteca de ícones padrão

**Context:** Precisávamos definir uma biblioteca de ícones para o stack do framework.
**Decision:** Usar lucide-animated como padrão (via shadcn registry: `pnpm dlx shadcn add @lucide-animated/{icon-name}`), lucide-react como fallback para ícones estáticos.
**Reason:** lucide-animated oferece 379+ ícones animados com Motion sem custo extra — Motion já está aprovado no stack. Integra-se nativamente com shadcn/ui.
**Trade-offs:** Ícones são instalados individualmente (não como pacote npm global). Aceito — segue o padrão shadcn/ui de componentes copiados.

## 2026-03-02 — Anti-Hallucination Protocol + Confidence Tagging + padronização de skills

**Context:** Análise revelou que agentes podiam fazer afirmações não verificadas com tom de certeza, e que skills sem exemplos levavam os agentes a inventar formatos. Maestro também não tinha triggers claros para rotear skills.
**Decision:** Adicionar Anti-Hallucination Protocol (SPEC §3.6) e Confidence Tagging `[CONFIRMED]/[ASSUMED]/[UNCERTAIN]` (SPEC §3.7) como protocolos universais. Adicionar seções "When to Use" e "Examples" (✅/❌) em todos os 16 skills.
**Reason:** Few-shot exemplos ancoram comportamento em LLMs; confidence tags tornam incerteza explícita; triggers de skill evitam roteamento incorreto pelo Maestro.
**Trade-offs:** Volume de edições alto (16 arquivos + SPEC + 2 personas). Aceito — é trabalho de setup, não de manutenção contínua.

<!-- Example format:

## 2026-02-25 — JWT over session cookies for auth

**Context:** Needed to choose an authentication strategy for the API.
**Decision:** Use JWT with short-lived access tokens (15min) and long-lived refresh tokens (7d).
**Reason:** Stateless auth simplifies horizontal scaling. Refresh tokens mitigate short expiry UX.
**Trade-offs:** Revocation requires a blocklist. Accepted for now; revisit if abuse is detected.

-->
