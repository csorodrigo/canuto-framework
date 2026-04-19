---
skill: ask-gemini
trigger: "/ask-gemini, or any time the user asks Gemini something directly without specifying which Gemini tool"
persona: maestro
version: 1.0.0
lastUpdated: 2026-04-18
shortDescription: >
  Ergonomic wrapper around mcp__gemini__ask-gemini. Picks sensible defaults
  (model, prompt prefix) so the user can write `/ask-gemini "pergunta"` instead
  of typing the full MCP call.
usedBy: [maestro]
evals:
  - prompt: "/ask-gemini liste todas as skills do framework"
    should_trigger: true
  - prompt: "pergunta pro gemini: que premissas esse plano viola?"
    should_trigger: true
  - prompt: "@.agents/skills/ resume cada skill"
    should_trigger: true
  - prompt: "review this code"
    should_trigger: false
---

## Purpose

Atalho ergonômico para chamar Gemini diretamente. Sem este skill o usuário tem que
digitar `mcp__gemini__ask-gemini({ prompt: "...", model: "gemini-3.1-pro-preview" })`
toda vez. Com `/ask-gemini` ele escreve só `/ask-gemini "pergunta"` e o skill aplica
defaults inteligentes.

Para casos passivos (skill auto-roteia), usar a skill específica (`/research`, `/auto-analysis`,
`/co-plan --triple`, etc). Este skill é só para chamada **ativa direta**.

---

## When to Use

**Triggers:**
- Usuário escreve `/ask-gemini "..."` ou `/gemini "..."`
- Usuário pede "pergunta pro Gemini", "ask gemini", "via Gemini"
- Prompt contém `@folder` ou `@arquivo.png` (long-context ou multimodal — slot Gemini-nativo)
- Usuário pede classificação em massa ou triagem (rotear pra `flash-lite`)

**Not for:**
- Code generation — sem sandbox; usar `mcp__codex-coder__spawn_agent`
- Decisões tier-1 (planning, architecture interview) — Opus direto
- Brainstorm estruturado SCAMPER/lateral — usar `mcp__gemini__brainstorm` direto (a tool dedicada é melhor)
- Tasks que exigem tooling do Codex — usar Codex
- Quando já existe skill passiva apropriada (`/research`, `/auto-analysis`, `/co-plan --triple`)

---

## Procedure

1. Parse a pergunta do usuário em `prompt`.
2. Detectar tipo da pergunta para escolher modelo:
   - Pergunta tem `@folder` ou `@arquivo` (long-context) → `gemini-3.1-pro-preview`
   - Pergunta tem `@*.png/jpg/webp` (multimodal) → `gemini-3.1-pro-preview` + lembrar gotcha de copiar pra workspace
   - Pergunta pede "classifique", "triage", "label", "1 palavra" (bulk) → `gemini-3.1-flash-lite-preview`
   - Default → `gemini-3.1-pro-preview`
3. Antes da chamada, consultar `gemini-routing.md` para gotchas relevantes.
4. Chamar:
   ```
   mcp__gemini__ask-gemini({
     prompt: "<prompt do usuário>",
     model: "<modelo escolhido>"
   })
   ```
5. Retornar resposta crua. Não reformatar, não resumir — usuário pediu Gemini, recebe Gemini.

---

## Defaults

| Param | Valor default | Override |
|---|---|---|
| model | `gemini-3.1-pro-preview` | usuário explicita: `--flash-lite` ou `--pro` |
| sandbox | `false` (sandbox não executa de qualquer jeito — ver gotcha #8) | nunca |

---

## Examples

### ✅ Good — long-context

```
Usuário: /ask-gemini @.agents/skills/ liste em bullets cada skill e seu propósito

Maestro:
mcp__gemini__ask-gemini({
  prompt: "@.agents/skills/ liste em bullets cada skill e seu propósito",
  model: "gemini-3.1-pro-preview"
})
→ retorna lista crua do Gemini
```

### ✅ Good — multimodal com aviso de gotcha

```
Usuário: /ask-gemini @~/Desktop/mockup.png que problemas de hierarquia tem aqui?

Maestro:
1. Aviso: "Gemini sandbox bloqueia ~/* — vou copiar pra .context/ primeiro."
2. cp ~/Desktop/mockup.png .context/mockup.png
3. mcp__gemini__ask-gemini({
     prompt: "@.context/mockup.png que problemas de hierarquia tem aqui?",
     model: "gemini-3.1-pro-preview"
   })
4. rm .context/mockup.png
```

### ✅ Good — bulk classify

```
Usuário: /ask-gemini classifique XS/S/M/L: "adicionar coluna created_at em users"

Maestro:
mcp__gemini__ask-gemini({
  prompt: "Classifique em 1 palavra (XS/S/M/L): 'adicionar coluna created_at em users'",
  model: "gemini-3.1-flash-lite-preview"
})
```

### ❌ Bad — code generation roteado pra Gemini

```
Usuário: /ask-gemini implementa a função de auth

Maestro: NÃO usar este skill. Gemini não tem sandbox.
Resposta correta: "Implementação requer sandbox — vou rotear pro Codex via /code."
mcp__codex-coder__spawn_agent({ prompt: "implementa função auth ..." })
```

### ❌ Bad — brainstorm estruturado neste wrapper

```
Usuário: /ask-gemini brainstorm 5 ideias estilo SCAMPER pra reduzir cold-start

Maestro: chamar a tool dedicada, não o wrapper genérico.
mcp__gemini__brainstorm({
  prompt: "5 ideias pra reduzir cold-start",
  methodology: "scamper",
  ideaCount: 5
})
```

---

## Integration

- **gemini-routing.md** — cheat-sheet de gotchas (sempre consultar antes de chamar)
- **cost-routing.md** — matriz que decide quando rotear pra Gemini (este skill é o caso "rotear ativo")
- **multi-provider.md** — tier table com slots Gemini
- **bulk-classify.md** — skill especializada em flash-lite (preferir essa para volume alto)
- **co-plan, research, auto-analysis, context-digest** — skills passivas que já chamam Gemini sob o capô
