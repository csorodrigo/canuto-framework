---
name: co-plan
description: Gate oficial de plan review pelo caminho reviewer do Codex, via wrapper codex-delegate.sh (modelo e effort vêm de .agents/config/models.yaml — hoje gpt-5.6-sol/xhigh, read-only).
---

# Co-Plan

Use quando o usuário pedir o gate oficial de plano. Não é consulta genérica ao Codex CLI.

O caminho canônico é o **wrapper**, nunca `codex exec` cru:

```
~/.codex/bin/codex-delegate.sh reviewer <task-file> <out-file>
```

> **Por que o wrapper e não `codex exec --profile reviewer`** (a forma que esta
> skill usava até 2026-07-26):
> - `--profile` está morto no caminho de delegação: o wrapper nunca o passa, e o
>   codex-cli 0.135+ não lê mais os blocos `[profiles.*]` de `config.toml`.
> - `codex exec` cru omite `-s` e herda `sandbox_mode="danger-full-access"` +
>   `approval_policy="never"` do `config.toml`. Para um **review**, isso é o
>   oposto do que se quer: o wrapper força `read-only` no role reviewer.
> - O wrapper encapsula stdin-hang, timeout, checagem de 0-byte, pré-flight de
>   auth e métricas em `~/.codex/delegate-metrics.jsonl`. `codex exec` cru não
>   deixa rastro auditável.
> - **`-q` foi removido no codex-cli 0.135.** Esta skill embarcava `-q` em duas
>   invocações (o path `--dual`), então essas chamadas falhavam instantaneamente
>   com `unexpected argument '-q'`. Essa classe de erro produziu ~194 fallbacks
>   silenciosos para Claude quando a 0.135 saiu. Nunca use `-q`.

## Execução

1. Localizar o plano ativo, nesta ordem:
   - `plan_file_path` da resposta de tool atual
   - `PLAN.md`, `plan.md` ou `PLAN.txt` no repo
   - o arquivo mais recente em `~/.claude/plans/`
2. Ler o plano completo e montar o arquivo de task.
3. Invocar o reviewer:

```bash
cat > /tmp/co-plan-task-$$.md <<'PROMPT'
You are reviewing an implementation plan before coding starts.
Review only the embedded plan below.
Find logical gaps, hidden dependencies, missing validation/test strategy,
rollback gaps, bad sequencing, and simpler alternatives.
Be direct. Be terse. No compliments.

THE PLAN:
<embedded plan>
PROMPT

~/.codex/bin/codex-delegate.sh reviewer /tmp/co-plan-task-$$.md /tmp/co-plan-review-$$.md
```

4. **Verificar que rodou de fato antes de reportar.** Não basta o comando
   retornar: a falha se detecta na métrica, não no rc.
   - Falha = última linha de `~/.codex/delegate-metrics.jsonl` com
     `result != "OK"` **ou** `bytes == 0`.
   - `rc` mente nas duas direções: existem runs com `rc:0` e
     `result != OK`, e runs com `result:"OK"` e `bytes:0` (mortos em 1-3s).
   - Se deu TIMEOUT, procure o parcial resgatado em
     `/tmp/co-plan-review-$$.md.partial.md` antes de re-delegar.
5. Reportar a proveniência real:
   - `reviewerPath: codex-delegate.sh reviewer`
   - `model`: o que a métrica registrou (não o que você esperava)
   - `effort`, `sandbox: read-only`
   - `fallbackOccurred: false`
6. Se o wrapper falhar (exit 4/5), degradar **declarando explicitamente**:
   - respawn da mesma task file como subagente Claude
   - Claude-only review por último (`fallbackOccurred: true` + motivo)
   - **Nunca** afirme que o reviewer Codex rodou sem a métrica confirmando.

## Required Output

Todo resultado de `/co-plan` deve declarar:
- `reviewerPath`
- `model` (lido da métrica)
- `fallbackOccurred`
- `verdict`
- `issues` ou `clean`

---

## `/co-plan --dual`

Para planos estratégicos onde o custo de uma decisão errada > custo do dual review,
use a variante dual: self-review do Claude + Codex reviewer, com escalação para
architect em paralelo.

### Quando usar
- Planos que afetam arquitetura (novos módulos, microserviços, schema changes)
- Planos com dependências externas (APIs pagas, integrações críticas)
- Planos de segurança ou compliance
- Quando o usuário pede `--dual` explicitamente ou o plano é crítico

### Fluxo (2 streams paralelos)

```
Stream A — Claude (self-review):
  Claude consolida o plano próprio com análise de premissas.

Stream B — Codex reviewer (engineering adversarial, read-only):
  ~/.codex/bin/codex-delegate.sh reviewer \
    /tmp/co-plan-task-$$.md /tmp/codex-review-$$.md

(opcional) Stream C — Codex architect (premise check, effort xhigh):
  ~/.codex/bin/codex-delegate.sh architect \
    /tmp/co-plan-arch-$$.md /tmp/codex-arch-$$.md
  Task file: "Review this plan against the repo. Que premissas desse plano o
  código existente contradiz?"
  Use Stream C só se a complexidade justificar (>50 arquivos afetados, ou
  refactor cross-module).
```

Os dois streams Codex rodam com modelo e effort de `.agents/config/models.yaml`
(reviewer: xhigh/read-only; architect: xhigh/workspace-write). Não pinar modelo
inline aqui — pinar em dois lugares é como a defasagem começa.

### Síntese
Claude consolida os streams:
- **Convergência** (Claude + Codex concordam) → high-confidence issue, fix mandatório
- **Divergência** → evaluate — Claude apresenta os dois lados
- **Issue Codex-only** ou **Claude-only** → discuss before deciding

### Output
Mesmo formato do `/co-plan` normal, mais uma seção "## Dual review matrix"
mostrando quem levantou cada issue e o `result` da métrica de cada stream.

### Não usar `/co-plan --dual` se:
- XS/S task (dual overhead > benefit)
- Plan muda só 1 arquivo
- User está em modo de iteração rápida (trade-off de latência)

> **Nota histórica (2026-04-29)**: esta skill suportava `/co-plan --triple` com
> Gemini como Stream C. Gemini foi removido do framework; Stream C agora é
> opcional via role architect. Detalhes em `docs/FEATURE-MAP.md`.
>
> **Nota histórica (2026-07-26)**: as invocações desta skill usavam
> `codex exec --profile <role>` com `-q`. `-q` foi removido no codex-cli 0.135,
> e `--profile` não é lido pelo wrapper — ou seja, o gate oficial de plano
> falhava ou rodava fora do caminho auditável. Convertido para o wrapper.
