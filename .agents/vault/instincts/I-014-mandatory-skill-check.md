---
type: instinct
id: I-014
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
  - maestro
  - skills
  - enforcement
---

# Skills sem enforcement são documentação morta — a 1% Rule corrige isso

**Pattern:** Antes de qualquer roteamento ou ação não-trivial, verificar se existe um skill aplicável em `.agents/skills/`. Se há 1% de chance de aplicação, o skill DEVE ser lido. Racionalizações para pular ("é simples", "já sei como fazer") são sempre erradas.

**Learning:** O framework tinha 48+ skills mas nenhum mecanismo que forçasse sua consulta. O resultado era inconsistência: agents aplicavam skills quando se lembravam, não sistematicamente. A 1% Rule (de `obra/superpowers`) muda o padrão cognitivo de "consulto se precisar" para "consulto por padrão, pulo só se claramente inaplicável". Skills existem exatamente para actions que parecem simples — onde inconsistência custa mais que o custo de leitura.

**Source:** [[sessions/2026-03-23]] — adotado de obra/superpowers, mapeado para Step 0 do Maestro
