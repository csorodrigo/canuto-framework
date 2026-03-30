shortDescription: "[DEPRECATED] Use co-review skill instead. Legacy Codex plan review via shell hook."
usedBy: [maestro]
version: 1.1.0
lastUpdated: 2026-03-29
deprecated: true
supersededBy: co-review
copyright: Rodrigo Canuto © 2026.

## ⚠️ DEPRECATED

**This skill is superseded by `co-review.md`.** The co-review skill provides the same functionality plus:
- Bias-free parallel review (complete your work before seeing Codex's output)
- Three modes: brainstorm, plan, validate
- MCP-based multi-turn communication (clarifying questions supported)
- Background subagent pattern for true parallel work

To migrate: configure Codex MCP (`codex-coder` + `codex-reviewer`) and use `/co-validate` instead. The legacy hook `plan-review.sh` now runs on `PostToolUse: ExitPlanMode` with the reviewer profile as a fallback.

---

## Purpose (Legacy)

Obter uma segunda opinião independente sobre o plano criado pelo Architect antes de passar ao Coder. Um hook automático chama o Codex CLI ao sair do plan mode, identificando riscos, lacunas e alternativas que o Architect pode ter ignorado.

Dois modelos competindo = saída de qualidade mais alta.

---

## When to Use

**Triggers:**
- Architect finaliza o plano e chama `ExitPlanMode` em tasks **M ou L**
- O hook `PostToolUse: ExitPlanMode` dispara automaticamente (não requer ação manual do Maestro)

**Not for:**
- Tasks **XS** ou **S** — overhead não vale o custo
- Quando o Codex CLI não está instalado — falha silenciosa, fluxo continua normalmente

---

## Pré-requisito

O Codex CLI deve estar instalado:

```bash
npm install -g @openai/codex
```

Verifique com: `codex --version`

---

## Como Funciona

O hook roda **fora** do contexto do Claude (shell bash), então o resultado aparece como saída do hook no terminal. O Maestro deve:

1. **Aguardar** o output do hook antes de rotear ao Coder
2. **Apresentar** o resultado ao usuário com contexto claro
3. **Aguardar aprovação** do usuário antes de prosseguir

---

## Procedure

1. Architect conclui o plano e chama `ExitPlanMode`
2. Hook `PostToolUse: ExitPlanMode` aciona `~/.claude/hooks/plan-review.sh`
3. Script localiza o arquivo de plano (path via stdin do hook)
4. Chama `codex exec --dangerously-bypass-approvals-and-sandbox` com prompt adversarial focado em:
   - O que pode fazer o plano falhar?
   - Quais dependências ocultas ou edge cases foram ignorados?
   - Existe uma alternativa mais simples?
   - Há premissas incorretas ou não verificadas?
5. Retorna resultado ao terminal

---

## Output do Codex

Se o plano estiver sólido:
```
════════════════════════════════
  Segunda Opinião — Codex
════════════════════════════════
✓ LGTM — plano sólido
════════════════════════════════
```

Se houver preocupações (máximo 5 bullet points):
```
════════════════════════════════
  Segunda Opinião — Codex
════════════════════════════════
⚠️ Pontos de atenção:
- [risco ou lacuna]
- [premissa não verificada]
- [alternativa mais simples]
════════════════════════════════
```

---

## Ação do Maestro após o hook

| Resultado do Codex | Ação do Maestro |
|---|---|
| `✓ LGTM` | Anunciar aprovação e rotear ao Coder |
| Concerns levantados | Apresentar ao usuário, oferecer: (a) revisar com Architect ou (b) prosseguir mesmo assim |

Announcement quando ✓ LGTM:
```
[Segunda Opinião — Codex] ✓ Plano aprovado.
Roteando ao Coder.
```

Announcement quando há concerns:
```
[Segunda Opinião — Codex] ⚠️ Foram levantados pontos de atenção.
Revisar com o Architect ou prosseguir mesmo assim?
```

---

## Examples

### ✅ Good — Maestro aguarda e apresenta resultado

```
[Architect → ExitPlanMode] Plano criado.
[Hook] Consultando Codex para segunda opinião...
[Segunda Opinião — Codex] ⚠️ 2 pontos levantados.
Apresentando ao usuário antes de rotear ao Coder.
```

### ❌ Bad — Maestro ignora o hook e roteia direto ao Coder

```
[Architect → Coder] Implementando o plano.
```

Isso é errado porque ignora o feedback da segunda opinião, anulando o valor da skill.

---

## Anti-Patterns — DO NOT

- DO NOT rodar em tasks XS/S — overhead não justificado
- DO NOT ignorar o feedback do Codex e rotear ao Coder sem apresentar ao usuário
- DO NOT bloquear o fluxo se o Codex não estiver instalado — falha silenciosa
- DO NOT tratar "✓ LGTM" como guarantee — é uma segunda opinião, não uma prova
- DO NOT substituir o Architect pelo Codex — o Codex revisa, não planeja
