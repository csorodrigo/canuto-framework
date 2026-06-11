shortDescription: Quando e como usar /office-hours + /plan-ceo-review antes do Architect em tasks L/XL com feature nova.
usedBy: [maestro]
version: 1.0.0
lastUpdated: 2026-03-20
copyright: Rodrigo Canuto © 2026.

## When to Use

**Triggers:**
- Task classificada como L ou XL
- Feature nova que ainda não existe no FEATURE-MAP.md
- Usuário apresentou uma ideia vaga ("quero adicionar...", "e se a gente fizesse...")
- Escopo parece grande ou incerto antes do Architect planejar

**Not for:**
- Bugs (use /investigate)
- Refactors de código existente
- Tasks XS/S com escopo bem definido
- Features que o usuário já especificou em detalhe com requisitos claros

---

## Purpose

O Canuto Framework é excelente na execução — mas a execução do problema **errado** custa mais do que não executar. Este skill define quando e como inserir a camada de validação de produto antes de o Architect criar o plano técnico.

A sequência completa para features L/XL:

```
Maestro detecta feature nova L/XL
  → Sugere ao usuário: "Quer rodar /office-hours antes de eu passar ao Architect?"
  → Usuário aprova
  → /office-hours (validação de problema + escolha de abordagem)
  → /plan-ceo-review [opcional, se escopo ainda parecer grande]
  → Architect (recebe o output do office-hours como contexto)
  → fluxo normal...
```

---

## Protocolo do Maestro

### Decisão de Recomendar Product Review

O Maestro **deve** sugerir product review quando:

1. A task tem sizing M/L/XL **E** é uma feature nova (não existe no FEATURE-MAP.md)
2. O usuário usa linguagem vaga: "quero tentar", "poderia ser interessante", "e se..."
3. A task implica mudanças em mais de 2 domínios diferentes do sistema
4. A última sessão teve rework alto relacionado a escopo mal definido (checar `instincts.md`)

O Maestro **não deve** sugerir quando:
- O usuário já forneceu um design doc ou especificação detalhada
- A feature foi discutida na sessão anterior e está documentada em `.context/`
- O usuário explicitamente pediu para ir direto ao código

### Como Sugerir (script do Maestro)

```
"Antes de passar ao Architect, recomendo rodar /office-hours para validar
o escopo e escolher a melhor abordagem. Isso leva ~15 min e pode evitar
retrabalho depois. Quer fazer isso agora?"
```

Se o usuário aceitar: instrua a invocar `/office-hours`.
Se o usuário recusar: prossiga com o Architect normalmente, sem insistir.

### Handoff para o Architect

Quando o output do `/office-hours` estiver pronto, o Maestro instrui o Architect:

```
"Leia o arquivo .context/office-hours-{feature}-{data}.md antes de criar
o plano técnico. A abordagem escolhida é {abordagem}. Esforce estimado: {sizing}."
```

O Architect deve confirmar que leu o arquivo antes de prosseguir.

---

## /plan-ceo-review — Quando Adicionar

Use `/plan-ceo-review` (disponível via gstack) **somente** quando:

- O scope do office-hours ainda parecer grande depois das 6 perguntas
- O usuário quiser um "segundo olhar" no escopo antes do Architect
- A feature tem alto impacto de produto (ex: nova área de produto, mudança de pricing, onboarding)

**Não é necessário** em toda task L/XL — é um layer extra para decisões de alto impacto.

---

## Relacionamentos com Outros Skills

- Outputs de `/office-hours` → input do Architect via `.context/office-hours-*.md`
- `/plan-ceo-review` e `/plan-eng-review` → disponíveis via gstack, complementam o Architect
- `/document-release` → invocado ao final, após ship da feature validada aqui
- `session-goals.md` → registre o goal da feature após o office-hours para rastrear progresso
