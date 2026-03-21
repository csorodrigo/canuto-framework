# Plano: Obsidian-Native Memory — Full Migration

> Canuto Framework → Obsidian Vault nativo com MCP obrigatório
> Vault location: `.agents/vault/` (dentro do repo)
> Estratégia: Migrar arquivos existentes para formato atomizado Obsidian

---

## Visão Geral da Arquitetura

### Antes (flat files)
```
.agents/memory/
  last-session.md       ← overwritten
  decisions.md          ← append-only monolito
  pending.md            ← overwritten
  instincts.md          ← append-only monolito
  metrics.md            ← append-only monolito
  audit-log.md          ← append-only monolito
  design-profile.md     ← single file
  component-inventory.md ← single file
  repo-index.json       ← machine-readable
```

### Depois (Obsidian vault atomizado)
```
.agents/vault/
  .obsidian/                     ← config do Obsidian (templates, plugins)
    plugins/
      obsidian-local-rest-api/   ← plugin REST API (obrigatório para MCP)
    templates/
      decision.md                ← template para novas decisões
      instinct.md                ← template para novos instincts
      session.md                 ← template para sessões
      metric.md                  ← template para métricas
      audit-event.md             ← template para eventos

  sessions/                      ← daily notes por sessão
    2026-03-21.md                ← sessão atual (goals, what was done, etc.)
    ...

  decisions/                     ← 1 nota por decisão (atomizada)
    D-001-lucide-animated.md     ← wikilinks para instincts, sessões
    D-002-anti-hallucination.md
    ...

  instincts/                     ← 1 nota por instinct (atomizada)
    I-001-rework-detection.md    ← frontmatter: confidence, category, applied
    ...

  pending/                       ← 1 nota por task pendente
    task-auth-tests.md           ← frontmatter: blocked-by, priority, session
    ...

  audit/                         ← 1 nota por evento significativo
    2026-03-21-SESSION_START.md
    2026-03-21-HANDOFF-maestro-architect.md
    ...

  metrics/                       ← 1 nota por sessão de métricas
    2026-03-21-metrics.md        ← frontmatter com dados estruturados
    ...

  design/                        ← design profile + component inventory
    profile.md                   ← design profile completo
    components/                  ← 1 nota por componente
      button.md
      card.md
      ...

  canvas/                        ← visual maps
    persona-flow.canvas          ← fluxo Maestro → Architect → Coder → ...
    feature-map.canvas           ← mapa visual de features
    ...

  bases/                         ← database views
    instincts-by-confidence.base ← query: instincts filtrados por confiança
    decisions-timeline.base      ← query: decisões em ordem cronológica
    pending-tasks.base           ← query: tasks pendentes por prioridade
    audit-by-type.base           ← query: audit events por tipo
    metrics-dashboard.base       ← query: métricas agregadas
    ...

  _index.md                      ← MOC (Map of Content) — entry point do vault
```

---

## Fases de Implementação

### Fase 1: Estrutura do Vault + Skills Import
**O que:** Criar a estrutura de diretórios do vault, importar/adaptar skills do kepano, configurar templates.

**Tarefas:**
1. Criar estrutura de diretórios `.agents/vault/`
2. Criar `.obsidian/` com config mínima (community-plugins.json, app.json)
3. Importar e adaptar as 5 skills do kepano como skills do Canuto:
   - `obsidian-markdown.md` → `.agents/skills/obsidian-markdown.md`
   - `obsidian-bases.md` → `.agents/skills/obsidian-bases.md`
   - `json-canvas.md` → `.agents/skills/json-canvas.md`
   - `obsidian-cli.md` → `.agents/skills/obsidian-cli.md`
   - `defuddle.md` → `.agents/skills/defuddle.md`
4. Criar templates Obsidian para cada tipo de nota (decision, instinct, session, etc.)
5. Criar `_index.md` (MOC) como entry point do vault

**Entregável:** Vault vazio mas estruturado, skills importadas, templates prontos.

---

### Fase 2: Frontmatter Schemas
**O que:** Definir schemas de frontmatter padronizados para cada tipo de nota.

**Schemas:**

#### Session Note
```yaml
---
type: session
date: 2026-03-21
mode: full | continue | targeted
goals:
  - { text: "Goal 1", status: done | partial | skipped }
personas-used: [maestro, architect, coder]
tasks-completed: 3
token-estimate: 45000
tags: [session, sprint-1]
---
```

#### Decision Note
```yaml
---
type: decision
id: D-001
date: 2026-03-21
status: active | superseded | deprecated
domain: stack | architecture | design | process
related-instincts: ["[[I-001]]"]
related-sessions: ["[[2026-03-21]]"]
tags: [decision, stack]
---
```

#### Instinct Note
```yaml
---
type: instinct
id: I-001
category: code-pattern | testing | architecture | debugging | design | process
confidence: low | medium | high
applied: 0
source-session: "[[2026-03-21]]"
last-seen: 2026-03-21
status: active | pruned | promoted
promoted-to: ""
tags: [instinct, confidence/high, category/testing]
---
```

#### Audit Event Note
```yaml
---
type: audit-event
event: SESSION_START | SESSION_END | HANDOFF | GATE | REWORK | ESCALATION | FLAG | BUDGET | INSTINCT
date: 2026-03-21T14:30:00
actor: maestro | architect | coder | tester | reviewer | debugger | contextualizer
session: "[[2026-03-21]]"
impact: low | medium | high
tags: [audit, handoff]
---
```

#### Pending Task Note
```yaml
---
type: pending-task
priority: high | medium | low
blocked-by: ""
created-session: "[[2026-03-21]]"
status: pending | in-progress | done | cancelled
tags: [pending, blocked]
---
```

#### Metric Note
```yaml
---
type: metric
session: "[[2026-03-21]]"
date: 2026-03-21
quality-verdict: APPROVE | REQUEST_CHANGES
must-fix-count: 0
test-failures: 0
debugger-invocations: 0
rework-cycles: 0
tasks-completed: 2
persona-transitions: 8
escalations: 0
format-compliance: 100
scope-violations: 0
tags: [metric]
---
```

#### Component Note
```yaml
---
type: component
source: shadcn | custom | third-party
path: src/components/ui/button.tsx
variants: [default, destructive, outline, ghost]
used-in: [page-a, page-b]
tags: [component, ui]
---
```

**Entregável:** Schemas documentados + templates atualizados com frontmatter.

---

### Fase 3: Migração dos Dados Existentes
**O que:** Migrar os 2 decisions existentes + templates para o novo formato.

**Tarefas:**
1. Migrar `decisions.md` → 2 notas individuais em `decisions/`
   - `D-001-lucide-animated.md`
   - `D-002-anti-hallucination.md`
2. Migrar `design-profile.md` → `design/profile.md` (mantém estrutura, adiciona frontmatter)
3. Migrar `component-inventory.md` → `design/components/` (vazio, mas template pronto)
4. Migrar `last-session.md` template → `sessions/` template
5. Migrar `pending.md` template → `pending/` template
6. Migrar `instincts.md` template → `instincts/` template
7. Migrar `metrics.md` template → `metrics/` template
8. Migrar `audit-log.md` template → `audit/` template
9. Manter `repo-index.json` em `.agents/memory/` (não faz parte do vault)

**Entregável:** Dados existentes migrados, vault populado.

---

### Fase 4: Bases (Database Views)
**O que:** Criar `.base` files para queries estruturadas sobre a memória.

**Bases a criar:**
1. `instincts-by-confidence.base` — Tabela de instincts agrupados por confidence (high → low)
2. `decisions-timeline.base` — Decisões em ordem cronológica com status
3. `pending-tasks.base` — Tasks pendentes ordenadas por prioridade
4. `audit-by-type.base` — Eventos de audit agrupados por tipo (HANDOFF, GATE, etc.)
5. `metrics-dashboard.base` — Métricas por sessão com summaries (avg, min, max)
6. `components-registry.base` — Componentes por source (shadcn, custom, third-party)

**Entregável:** 6 bases funcionais para consulta de memória.

---

### Fase 5: Canvas (Visual Maps)
**O que:** Criar canvases para visualizações do framework.

**Canvases a criar:**
1. `persona-flow.canvas` — Fluxo visual: Maestro → Architect → Coder → Tester → Reviewer (com Debugger branch)
2. `memory-map.canvas` — Mapa visual de como os tipos de nota se conectam (sessions → decisions → instincts)

**Entregável:** 2 canvases funcionais.

---

### Fase 6: MCP Integration
**O que:** Configurar o MCP server como obrigatório e atualizar o framework.

**Tarefas:**
1. Criar `.agents/mcp/` com configuração do MCP server:
   - `server.json` — config do obsidian-mcp-server
   - `setup.md` — instruções de setup (instalar plugin REST API, gerar API key, etc.)
2. Criar skill `mcp-obsidian.md` em `.agents/skills/` — como o framework usa MCP para:
   - Buscar notas: `obsidian_global_search`
   - Ler notas: `obsidian_read_note`
   - Criar notas: `obsidian_update_note` (create mode)
   - Atualizar frontmatter: `obsidian_manage_frontmatter`
   - Gerenciar tags: `obsidian_manage_tags`
3. Atualizar `CLAUDE.md` com instruções de MCP obrigatório

**Entregável:** MCP configurado, skill de integração criada.

---

### Fase 7: Session Lifecycle Update
**O que:** Atualizar Maestro e Contextualizer para usar o vault Obsidian.

**Tarefas:**
1. Atualizar `maestro.md`:
   - Session start: ler `sessions/` (última sessão), `pending/` (tasks pendentes), `instincts/` (ativos)
   - Session end: criar nota em `sessions/`, criar notas em `pending/`, extrair instincts
   - Usar wikilinks em todas as referências cruzadas
2. Atualizar `contextualizer.md`:
   - Bootstrap: criar `.context.md` como antes, mas linkar via wikilinks no vault
   - Stale check: mesmo protocolo, resultados logados no vault
3. Atualizar skills de memória:
   - `continuous-learning.md` → criar notas individuais de instinct
   - `audit-trail.md` → criar notas individuais de audit event
   - `metrics.md` → criar notas individuais de métricas
   - `session-goals.md` → integrar com session notes
4. Atualizar `SPEC.md` seção 5 (Memory & Session Persistence) com nova estrutura

**Entregável:** Lifecycle completo migrado para vault.

---

### Fase 8: Cleanup & Documentation
**O que:** Remover sistema antigo, documentar o novo.

**Tarefas:**
1. Remover `.agents/memory/` (migrado para `.agents/vault/`)
   - Manter `repo-index.json` (mover para `.agents/vault/` ou `.agents/`)
2. Atualizar `README.md` com novo sistema de memória
3. Atualizar `install.sh` com setup do vault + MCP
4. Atualizar `registry.md` com novas skills (obsidian-markdown, obsidian-bases, etc.)
5. Atualizar `CLAUDE.md` com novo `On Session Start` flow

**Entregável:** Framework limpo, documentado, pronto para uso.

---

## Resumo de Impacto

### Arquivos Novos (criados)
- `.agents/vault/` — toda a estrutura do vault (~30+ arquivos)
- `.agents/skills/obsidian-markdown.md` — skill importada
- `.agents/skills/obsidian-bases.md` — skill importada
- `.agents/skills/json-canvas.md` — skill importada
- `.agents/skills/obsidian-cli.md` — skill importada
- `.agents/skills/defuddle.md` — skill importada
- `.agents/skills/mcp-obsidian.md` — skill de integração MCP
- `.agents/mcp/server.json` — config MCP
- `.agents/mcp/setup.md` — guia de setup MCP

### Arquivos Modificados
- `.agents/SPEC.md` — seção 5 reescrita
- `.agents/personas/maestro.md` — session lifecycle atualizado
- `.agents/personas/contextualizer.md` — integração com vault
- `.agents/skills/continuous-learning.md` — formato atomizado
- `.agents/skills/audit-trail.md` — formato atomizado
- `.agents/skills/metrics.md` — formato atomizado
- `.agents/skills/session-goals.md` — integração com session notes
- `CLAUDE.md` — MCP obrigatório + novo session start
- `README.md` — documentação atualizada
- `install.sh` — setup do vault + MCP
- `registry.md` — novas skills registradas

### Arquivos Removidos
- `.agents/memory/` — todo o diretório (migrado para vault)

### Dependências Externas Novas
- **Obsidian** (app desktop) — obrigatório
- **Obsidian Local REST API** (community plugin) — obrigatório para MCP
- **obsidian-mcp-server** (npm) — obrigatório (`npx obsidian-mcp-server`)
- **defuddle** (npm) — recomendado (`npm install -g defuddle`)

---

## Riscos e Mitigações

| Risco | Mitigação |
|-------|-----------|
| Obsidian não roda em CI/CD headless | Vault funciona como markdown puro. Bases e busca MCP não disponíveis em CI, mas notas são legíveis |
| MCP server é single-maintainer | Apache 2.0 license permite fork. Vault é filesystem, não locked-in |
| Setup mais complexo que antes | `install.sh` automatiza. `setup.md` documenta passo a passo |
| Performance com vault grande | Cache do MCP server + refresh de 10min. Para vaults de framework, tamanho é trivial |
| Conflitos de git em vault | `.obsidian/workspace.json` vai para `.gitignore`. Notas são markdown, merge-friendly |
