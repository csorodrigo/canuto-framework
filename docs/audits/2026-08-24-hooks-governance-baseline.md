# Baseline de governança dos hooks

Status: T0 concluída em 2026-08-24. Este lote somente versiona evidência de
auditoria. Nenhuma configuração ou cópia instalada foi alterada.

## Fonte e identidade

- repositório: `csorodrigo/canuto-framework`;
- base: `main` em `180c74751250de0f57555f6618c912bd341cc9cf`;
- branch da tarefa: `codex/hooks-governance-t0`;
- estado inicial da worktree: limpo;
- fixture: [active-hooks-2026-08-24.json](../../.agents/hooks/audit/fixtures/active-hooks-2026-08-24.json);
- manifesto: [provenance-manifest.json](../../.agents/hooks/audit/provenance-manifest.json).
- receipts de fonte dos plugins: [plugin-source-receipts.json](../../.agents/hooks/audit/plugin-source-receipts.json).

A captura lê somente a propriedade `hooks` das entradas JSON. O artefato não
contém comandos brutos, prompts, nomes ou valores de campos sensíveis, nem
caminhos absolutos. Comandos e arquivos executáveis são representados por
SHA-256; caminhos de artefato são reduzidos ao nome-base.

## Reconciliação

| Superfície | Registros |
|---|---:|
| Claude — configuração do usuário | 57 |
| Codex — configuração do usuário | 17 |
| Plugin Vercel 0.45.1 | 4 |
| Plugin Codex Companion 1.0.5 | 3 |
| **Total** | **81** |

O validador também fixa a distribuição por evento: `PreToolUse` 36,
`PostToolUse` 13, `SessionStart` 11, `Stop` 8, `SessionEnd` 5,
`Notification` 2 e um registro em cada evento restante documentado na fixture.

Cada registro possui ID estável, superfície, evento, matcher, timeout, papel,
responsável, destinação, digest do comando, digests dos artefatos encontrados e
estado de proveniência. O manifesto liga essas atribuições ao hash exato da
fixture para impedir que uma revisão use inventário e responsabilidade de
snapshots diferentes.

## Resultado de proveniência

| Estado | Registros | Consequência |
|---|---:|---|
| Fonte Canuto idêntica | 17 | Elegível apenas para um plano operacional posterior |
| Plugin versionado, pinado e idêntico | 6 | Elegível apenas para um plano operacional posterior |
| Remoção já aprovada pela matriz | 13 | Elegível apenas para um plano operacional posterior |
| Fonte divergente ou parcial | 6 | Lote bloqueado |
| Fonte versionada ausente | 39 | Lote bloqueado |
| **Total** | **81** |  |

Os seis registros com fonte parcial ou divergente são `CU-29`, `CU-33`,
`CX-10`, `CX-13`, `CX-14` e `PV-02`. Em `PV-02`, o artefato do cache instalado
difere do arquivo no commit pinado do repositório Vercel, embora o manifesto de
hooks coincida. Os outros 39 bloqueios têm responsável e destino
registrados, mas ainda não possuem uma fonte versionada que reproduza o handler
instalado. Eles não foram importados da cópia pessoal.

Assim, 81/81 registros estão reconciliados com proprietário e destinação, mas
45 permanecem em `blocked-source-provenance`. Essa é a parada obrigatória da T0:
nenhum desses registros pode entrar em plano de instalação, substituição ou
migração até a fonte indicada existir e o digest ser revalidado. O estado
`eligible-for-later-plan` não autoriza `apply`, instalação ou edição de
configuração.

## Reprodução segura

A captura exige todos os caminhos explicitamente e cria o arquivo de saída com
semântica exclusiva; ela não sobrescreve uma fixture existente.

```bash
audit_output_dir="$(mktemp -d)"
node .agents/hooks/audit/capture-hooks-baseline.mjs capture \
  --claude-settings "$HOME/.claude/settings.json" \
  --codex-hooks "$HOME/.codex/hooks.json" \
  --home "$HOME" \
  --captured-at "2026-08-24T21:00:00-03:00" \
  --base-sha "$(git rev-parse origin/main)" \
  --branch "$(git branch --show-current)" \
  --vercel-version 0.45.1 \
  --vercel-hooks "$HOME/.claude/plugins/cache/claude-plugins-official/vercel/0.45.1/hooks/hooks.json" \
  --companion-version 1.0.5 \
  --companion-hooks "$HOME/.claude/plugins/cache/openai-codex/codex/1.0.5/hooks/hooks.json" \
  --output "$audit_output_dir/active-hooks.json"
```

Validação do snapshot versionado:

```bash
node .agents/hooks/audit/capture-hooks-baseline.mjs validate \
  .agents/hooks/audit/fixtures/active-hooks-2026-08-24.json
node .agents/hooks/audit/capture-hooks-baseline.mjs validate-provenance \
  .agents/hooks/audit/provenance-manifest.json \
  .agents/hooks/audit/fixtures/active-hooks-2026-08-24.json
```

O teste de captura usa diretórios temporários e prova que propriedades fora de
`hooks` não aparecem na saída. Nenhum teste lê ou modifica a configuração real.
