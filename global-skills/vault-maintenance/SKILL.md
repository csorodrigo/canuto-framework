---
name: vault-maintenance
description: Manutenção periódica do vault Obsidian — arquiva sessões antigas, agrega métricas e audits, limpa snapshots.
type: global-skill
version: 1.0.0
lastUpdated: 2026-03-22
copyright: Rodrigo Canuto © 2026
---

# /vault-maintenance — Vault Maintenance

Manutenção periódica do vault Obsidian para evitar crescimento descontrolado e manter queries rápidas.

## Quando Usar

- **Automaticamente**: Maestro sugere quando total de notes > 500
- **Manualmente**: `/vault-maintenance` a qualquer momento
- **Trimestralmente**: recomendado como housekeeping regular

---

## Protocolo

### Fase 1 — Assessment

Conte total de notes no vault:

```
obsidian_global_search(query="type:", contextLength=10)
```

Apresente:
```
Vault Maintenance Assessment:
- Total notes: {count}
- Projects: {project_count}
- Oldest session: {date}
- Largest project: {name} ({count} notes)
```

### Fase 2 — Arquivar Sessões Antigas (> 90 dias)

Para cada projeto:
1. Encontre sessões com mais de 90 dias: `projects/{slug}/sessions/YYYY-MM-DD.md`
2. Agrupe por trimestre (Q1, Q2, Q3, Q4)
3. Crie nota resumo: `projects/{slug}/sessions/archive/YYYY-Q{n}-summary.md`
   - Frontmatter: `type: session-archive`, `quarter`, `session_count`, `goals_achieved`, `goals_deferred`
   - Body: bullet list com goals e outcomes de cada sessão (1 linha por sessão)
4. Delete (ou mova) as notas individuais
5. Reporte: "Archived {n} sessions -> {m} quarterly summaries"

### Fase 3 — Arquivar Instincts Pruned (> 30 dias)

1. Encontre instincts com `status: pruned` e `last-seen` > 30 dias atrás
2. Mova para `projects/{slug}/instincts/archive/`
3. Reporte: "Archived {n} pruned instincts"

### Fase 4 — Agregar Audit Events Antigos (> 60 dias)

1. Encontre audit notes com mais de 60 dias
2. Agrupe por mês
3. Crie: `projects/{slug}/audit/YYYY-MM-summary.md`
   - Frontmatter: `type: audit-summary`, `month`, `event_count`, `types` (list)
   - Body: contagem por tipo de evento + eventos notáveis
4. Delete audit notes individuais
5. Reporte: "Aggregated {n} audit events -> {m} monthly summaries"

### Fase 5 — Agregar Métricas Antigas (> 90 dias)

1. Encontre metric notes com mais de 90 dias
2. Agrupe por trimestre
3. Crie: `projects/{slug}/metrics/YYYY-Q{n}-summary.md`
   - Frontmatter: `type: metrics-summary`, `quarter`, `session_count`
   - Body: médias de cada métrica (tasks_completed, rework_cycles, must_fix_count, etc.)
4. Delete metric notes individuais
5. Reporte: "Aggregated {n} metric notes -> {m} quarterly summaries"

### Fase 6 — Limpar Snapshots

1. Cheque `.snapshots/` em cada projeto
2. Delete snapshots com mais de 30 dias (mantenha no máximo 10 por projeto)
3. Reporte: "Cleaned {n} old snapshots"

---

## Confirmação Obrigatória

**SEMPRE peça confirmação antes de executar.** Apresente o assessment e ações propostas:

```
Proceed with vault maintenance? [Y/n]
```

Nunca delete ou arquive sem confirmação do usuário.

---

## Output Final

```markdown
## Vault Maintenance Report — YYYY-MM-DD

### Before
- Total notes: {before_count}
- Oldest unarchived session: {date}

### Actions Taken
- Sessions archived: {n} -> {m} quarterly summaries
- Pruned instincts archived: {n}
- Audit events aggregated: {n} -> {m} monthly summaries
- Metrics aggregated: {n} -> {m} quarterly summaries
- Snapshots cleaned: {n}

### After
- Total notes: {after_count}
- Reduction: {percentage}%

### Recommendations
- {sugestoes adicionais}
```

---

## Notas

- Notas arquivadas **NAO** são deletadas — são movidas para subdiretórios `archive/`
- Notas resumo preservam dados-chave para análise de tendências
- Bases ainda consultam notas arquivadas se o usuário navegar à pasta `archive/`
- Este skill complementa `analyze.sh` (análise) — este skill **toma ação**
