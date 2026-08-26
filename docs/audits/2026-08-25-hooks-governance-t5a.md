# T5a — estado desejado para aposentadorias

Status: T5a concluída como plano versionado em 2026-08-25. Nenhum `apply` foi
executado contra hooks, configurações ou arquivos instalados.

## Base e limite do lote

- base T4: `38cd2f98acfc7f0c2328fe843735d0b1b286fadb`;
- superfície Claude: `CU-40`, `CU-44`, `CU-46` e `CU-51`–`CU-56`;
- superfície Codex: `CX-02`;
- ação desejada: aposentar somente os dez registros;
- ação de arquivo: nenhuma;
- `CU-20` e `log-commands.sh` permanecem fora do lote porque `CU-41` ainda não
  foi desacoplado;
- o grupo `SessionStart` vazio e os demais itens de T5 ficam para outro lote.

As aposentadorias sem arquivo de origem são seletores de configuração, não
comandos executáveis. O reconciliador exige correspondência exata de superfície,
evento, matcher e comando. Entradas ativas continuam exigindo origem, SHA-256 e
modo `0755`; uma aposentadoria com propriedade de arquivo continua exigindo o
trio completo.

## Plan e fingerprint

Os fingerprints de fixture são determinísticos e não dependem de caminho
absoluto. As fixtures contêm os registros-alvo e entradas externas sentinela.

| Superfície | Remoções | Arquivos | Entradas externas | Fingerprint |
|---|---:|---:|---:|---|
| Claude usuário | 9 | 0 | 2 | `c41b099f5b04cbf103869a2b94942e8fc68633e38e5f3ebc9a7f8ebe00908f41` |
| Codex usuário | 1 | 0 | 2 | `5c8c1e45b60f48632dedda9f6249b11f8263d798fe1cbb742d9192b199401a2b` |

Um preview somente leitura das configurações instaladas produziu o plano
abaixo. Os hashes identificam o snapshot observado, sem registrar o conteúdo da
configuração.

| Superfície | Antes | Depois planejado | Entradas externas | Fingerprint |
|---|---|---|---:|---|
| Claude usuário | `72ec2245c219a29c1889cdf796d9dda377b4bb2c4199a214477d9538dc6c7a4d` | `c5a72332ac4f6ff7d1b23d9ad19cdffc07a85a91f8787377fb0eca480554beac` | 48 | `ff8ef142837bfd7f57bd0fd2c7345bf1357ceedab175242c971e09aa92608c63` |
| Codex usuário | `073469acc3e0d5a20d1440f57c3c972914690f694e9da08f48e7541f9a940dd2` | `d8bd2e368ef611160333db02a03e0ed3c11e8d0e9c4acc2b601593d32bdac41d` | 16 | `3426cee2d8a38e54e1353ba1ab04f3345d33808b5ec5c8b4cff4ff150ca30397` |

O plano instalado fica inválido se qualquer input sofrer drift. Ele não constitui
autorização para `apply` e deve ser gerado novamente no lote operacional.

## Prova de rollback isolada

O teste aplicou cada plano somente a uma cópia temporária `0600`, verificou a
convergência e executou rollback pelo `batchId`. Nenhum diretório instalado foi
usado como destino.

| Superfície | Batch de prova | Hash antes/restaurado | Hash aplicado | Verify | Modo restaurado |
|---|---|---|---|---|---|
| Claude usuário | `20260825122443193-c41b099f5b04` | `08bfa0b599f58cee1f43cff9a2381186419e5fda09a62b4dc0d0169204dafb0f` | `5635fafaa59f9e8502e5f09cf37fd3f7885976141e4948486ae3986840c0c38c` | `ok` | `sim` |
| Codex usuário | `20260825122443208-5c8c1e45b60f` | `5d98ee93517130e07c9737e08cbcb140eb1d3687c625178aa741b81523ba854f` | `5bf2549779b8c3107a695f599912e46588ddc2ebc9c7d50adf1acfce7f4b72aa` | `ok` | `sim` |

O teste também prova que `log-commands.sh`, `delivery-proof-gate.sh`, entradas
externas com metadados e grupos vazios externos permanecem estruturalmente
idênticos. O receipt liga os IDs e ações do plan ao fingerprint do estado
convergido; após o rollback, conserva esses dados e registra `rolled-back`.
Uma falha injetada na escrita do receipt verificado também restaura a
configuração e os arquivos anteriores e registra `restored-after-failure`.

## Contagem de aceite

A diferença entre o baseline versionado de 81 registros e os dez IDs deste lote
resulta em 71 registros: 48 no Claude usuário, 16 no Codex usuário e 7 em
plugins. `CU-20` e `CU-41` permanecem presentes.

## Reprodução segura

Plan somente leitura sobre fixtures versionadas:

```bash
node .agents/hooks/reconcile-hooks.mjs plan \
  --manifest .agents/hooks/managed-hooks-retirements.claude.json \
  --config .agents/hooks/contracts/fixtures/t5a-claude-before.json \
  --hooks-dir "$(mktemp -d)"

node .agents/hooks/reconcile-hooks.mjs plan \
  --manifest .agents/hooks/managed-hooks-retirements.codex.json \
  --config .agents/hooks/contracts/fixtures/t5a-codex-before.json \
  --hooks-dir "$(mktemp -d)"
```

Prova automatizada de plan, fingerprint, preservação e rollback:

```bash
node --test .agents/hooks/reconcile-hooks.test.mjs \
  .agents/hooks/retirement-canary.test.mjs
```
