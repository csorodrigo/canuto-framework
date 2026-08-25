---
type: instinct
id: I-018
date: 2026-03-23
confidence: high
domain: skills
occurrences: 1
related-decisions: [D-011]
related-sessions: [sessions/2026-03-23c]
tags:
  - instinct
  - skills
  - evals
  - triggering
---

# I-014 — Near-misses São Mais Valiosos que Prompts Obviamente Negativos

Para testar se a `shortDescription` de uma skill tem triggering correto, os prompts `should_trigger: false` mais valiosos são near-misses — prompts que compartilham palavras-chave ou domínio mas precisam de uma skill diferente.

**Why:** "Escreva uma função fibonacci" como negativo para uma skill de PDF é fácil demais — não testa nada. O real risco de undertriggering/overtriggering está nos casos ambíguos: mesma tecnologia, objetivo diferente; mesmo problema, solução diferente; contexto parecido, persona errada.

**How to apply:**
- Ao escrever evals `should_trigger: false`, pergunte: "Que prompt pareceria similar mas precisaria de um skill diferente?"
- Exemplos de near-misses eficazes:
  - `health-check` near-miss: "verifique se o obsidian está sincronizando" (problema diferente, não é checagem do framework)
  - `continuous-learning` near-miss: "quantos instincts temos no vault?" (consulta, não extração)
  - `browser-qa` near-miss: "escreva testes unitários para o formulário" (testes, mas não browser)
