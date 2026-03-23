---
type: instinct
id: I-013
category: process
confidence: high
applied: 0
source-session: "2026-03-23"
last-seen: 2026-03-23
status: active
promoted-to: ""
tags:
  - instinct
  - process
  - coder
  - deviation
  - architect
---

# Deviation Taxonomy — 4 Categorias de Desvio do Plano

**Pattern:** Durante a implementação, o Coder frequentemente encontra situações não previstas pelo Architect: código existente que conflita, dependências ausentes, escopo que precisa crescer. Sem uma taxonomia clara, o Coder either silently deviates (risk) or over-escalates trivial changes (noise).

**Learning:** Classificar cada desvio em uma das 4 categorias antes de decidir como agir:

| Categoria | Definição | Ação |
|-----------|-----------|------|
| **[Acceptable]** | Detalhe de implementação ou otimização dentro do escopo — arquivos tocados iguais, objetivo intacto, interface pública preservada | Log na seção "Deviations from Plan", continua execução |
| **[Re-plan needed]** | Escopo mudou: arquivos além do planejado, nova dependência externa, contrato público alterado, passos adicionais necessários | Para, flageia ao Maestro com descrição do novo escopo. Não continua sem aprovação |
| **[Blocker]** | Conflito arquitetural, código legado incompatível, serviço externo indisponível, ou pre-condition impossível de satisfazer | Para imediatamente, escalada ao Maestro com contexto completo. Não tenta contornar |
| **[Goal impact]** | Um must-have do plano ficará parcialmente ou não entregue, ou um REQ-ID listado no plano está em risco | Flageia ao Maestro antes de continuar — nunca silencia um risco de requisito |

**Regra de desempate:** Em dúvida entre [Acceptable] e [Re-plan needed], trate como [Re-plan needed]. O custo de uma re-aprovação rápida é menor que o custo de rework após descoberta tardia.

**Source:** [[sessions/2026-03-23]] — derivado de GSD framework (gsd-build/get-shit-done) deviation rules, adaptado para persona flow do Canuto
