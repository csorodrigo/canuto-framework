# Canuto Framework — Tutorial Completo

## 1. Iniciando uma Sessao

Abra o Claude no diretorio do seu projeto. O Maestro automaticamente:

1. Determina o projeto pelo nome da pasta (ex: `prague`)
2. Carrega a memoria do vault (`~/.canuto/vault/projects/prague/`)
3. Verifica contextos desatualizados via git diff
4. Apresenta o briefing:

```
Session Briefing:
- Last session (2026-03-17): Implementou UX de reunioes completo.
- Deferred goals: none.
- Pending tasks: 2 (testes de integracao, refactor do cron).
- Active instincts: 3 high, 1 medium.
- Stale contexts: src/api/ (5 files changed).
```

5. Pede seus goals (ate 3):

> "What are your top goals for this session? (up to 3)"

### Modos de Sessao

| Voce diz | Modo | O que acontece |
|----------|------|----------------|
| *(goals novos)* | `full` | Sessao do zero, pending aparece no briefing |
| "Continue", "retoma" | `continue` | Pega pending tasks como goals, pula prompt de goals |
| "Quick fix", "so isso" | `targeted` | Foco estreito, ignora pending nao relacionado |

---

## 2. Durante a Sessao

### Fluxo padrao

```
Maestro → Architect → Coder → Tester → Reviewer
                                  ↓ (se testes falham)
                              Debugger → Coder (fix) → Tester (re-run)
```

O Maestro orquestra tudo. Voce so pede o que quer e ele delega.

### Comandos uteis durante a sessao

| Voce diz | O que acontece |
|----------|----------------|
| "health check" ou "check framework" | Roda diagnostico completo do framework |
| "set FAST_MODE" | Pula passos opcionais (Tester em tasks S, Design Lens) |
| "set STRICT_MODE" | Forca todos os checks, mesmo opcionais |
| "skip tests" ou "set SKIP_TESTER" | Pula o Tester (Coder → Reviewer direto) |
| "modo silencioso" ou "set QUIET_MODE" | So mostra erros e resultado final |
| "verbose" ou "set VERBOSE_HANDOFFS" | Handoffs completos com todo o contexto |
| "dry run" ou "set DRY_RUN" | Personas descrevem o que fariam sem executar |
| "budget strict" ou "set BUDGET_STRICT" | Para a sessao se estourar o budget de tokens |

### Flags ativas na sessao

Flags expiram quando a sessao termina. Para ver quais estao ativas, pergunte ao Maestro.

Conflitos resolvidos por prioridade:
- `STRICT_MODE` > `FAST_MODE`
- `STRICT_MODE` > `SKIP_TESTER`
- `VERBOSE_HANDOFFS` > `QUIET_MODE`

---

## 3. Encerrando uma Sessao

Diga: **"encerrar sessao"**, **"session end"**, ou **"finalizar"**.

O Maestro vai:

1. **Marcar goals** com status:
   - ✅ concluido
   - ⏳ parcial / adiado
   - ❌ nao iniciado

2. **Extrair instincts** — padroes aprendidos na sessao (rework, correcoes do usuario, rejeicoes). Pede aprovacao antes de salvar.

3. **Criar session note** em `projects/{projeto}/sessions/YYYY-MM-DD.md` com goals, o que foi feito, decisoes, links.

4. **Atualizar pending tasks** em `projects/{projeto}/pending/` — uma nota por task.

5. **Criar metricas** em `projects/{projeto}/metrics/YYYY-MM-DD-metrics.md`.

6. **Criar audit event** em `projects/{projeto}/audit/`.

7. **Sugerir cleanup** se 3+ tasks foram completadas.

### Hook automatico

O hook `session-save.sh` dispara automaticamente no Stop e cria um backup snapshot do vault. E uma rede de seguranca — nao substitui o fechamento formal pelo Maestro.

---

## 4. Slash Commands (Global Skills)

Disponiveis em **qualquer projeto**. Instalados em `~/.claude/skills/`.

### Canuto originals

| Comando | O que faz |
|---------|-----------|
| `/office-hours` | Reframe de produto estilo YC antes de codar. Forca as perguntas certas, gera 3 abordagens. |
| `/investigate` | Debugging forense. Iron Law: sem fix sem causa raiz confirmada. |
| `/document-release` | Atualiza toda a documentacao apos ship (README, FEATURE-MAP, CHANGELOG). |
| `/retro` | Retrospectiva semanal com metricas do framework. |

### Design skills (Impeccable)

| Comando | O que faz |
|---------|-----------|
| `/audit` | Scan de qualidade: acessibilidade, performance, responsividade, anti-patterns. |
| `/animate` | Adiciona animacoes e micro-interacoes com proposito. |
| `/bolder` | Transforma designs genericos em experiencias memoraveis. |
| `/clarify` | Melhora microcopy e textos de interface. |
| `/colorize` | Introducao estrategica de cor (60/30/10, OKLCH). |
| `/critique` | Avaliacao holistica de UX/design. |
| `/harden` | Resiliencia para producao: edge cases, overflow, i18n, erros. |
| `/overdrive` | Interfaces tecnicamente ambiciosas (View Transitions, WebGL, scroll-driven). |
| `/polish` | Passe final de qualidade antes do ship. |
| `/typeset` | Auditoria e melhoria de tipografia. |

### gstack (Garry Tan)

| Comando | O que faz |
|---------|-----------|
| `/plan-ceo-review` | Revisao de escopo nivel CEO. |
| `/plan-eng-review` | Revisao de arquitetura. |
| `/qa` | QA com browser Chromium real. |
| `/careful` | Guardrails contra operacoes destrutivas. |
| `/browse` | Pesquisa in-browser (requer bun). |
| `+16 mais` | Ver `~/.claude/skills/gstack/` |

---

## 5. Health Check

Diga: **"health check"**, **"check framework"**, **"diagnose"**, ou **"is the framework ok?"**

O Maestro verifica:
- CLAUDE.md (secoes obrigatorias)
- 7 personas presentes
- Core skills presentes
- Vault global (`~/.canuto/vault/`) e diretorios do projeto
- MCP conectividade
- Obsidian skills (flat files)
- Legacy check (memory/ antigo, SKILL.md em subdiretorios)
- SPEC.md

Resultado: **HEALTHY** | **DEGRADED** | **BROKEN**

---

## 6. Memoria e Obsidian

### O que e salvo automaticamente

| Tipo | Quando | Onde no vault |
|------|--------|---------------|
| Session note | Fim da sessao | `projects/{projeto}/sessions/YYYY-MM-DD.md` |
| Decisions | Quando Architect decide algo | `projects/{projeto}/decisions/D-XXX-slug.md` |
| Instincts | Fim da sessao (com aprovacao) | `projects/{projeto}/instincts/I-XXX-slug.md` |
| Pending tasks | Fim da sessao | `projects/{projeto}/pending/task-slug.md` |
| Metrics | Fim da sessao | `projects/{projeto}/metrics/YYYY-MM-DD-metrics.md` |
| Audit events | Durante a sessao | `projects/{projeto}/audit/YYYY-MM-DD-TYPE.md` |

### Visualizando no Obsidian

- **Graph view** (Ctrl/Cmd+G): mostra conexoes entre notas via wikilinks
- **Bases** (em `bases/`): tabelas filtraveis de instincts, decisions, metrics, pending
- **Canvas** (em `canvas/`): mapas visuais do framework

### Bases disponiveis

| Base | O que mostra |
|------|-------------|
| `instincts-by-confidence.base` | Instincts agrupados por confianca |
| `decisions-timeline.base` | Timeline de decisoes |
| `pending-tasks.base` | Tasks pendentes |
| `audit-by-type.base` | Eventos de audit por tipo |
| `metrics-dashboard.base` | Dashboard de metricas |
| `components-registry.base` | Registro de componentes UI |

---

## 7. Instalacao e Migracao — Referencia Rapida

```bash
# Fresh install (projeto novo)
curl -fsSL https://raw.githubusercontent.com/csorodrigo/canuto-framework/main/install.sh | bash

# Com API key (via curl pipe)
curl -fsSL .../install.sh | bash -s -- --api-key SUA_KEY

# Migrar de v1.5 (flat-file) para v1.6 (Obsidian vault)
curl -fsSL .../install.sh | bash -s -- --migrate --api-key SUA_KEY

# Atualizar framework (nao toca vault/plugins)
curl -fsSL .../install.sh | bash -s -- --update

# Instalar skill opcional
bash install.sh --skill adr --skill session-goals

# Checar versoes
bash install.sh --check
```

### Setup unico do Obsidian

1. Instale o Obsidian: [obsidian.md](https://obsidian.md)
2. File → Open folder as vault → `~/.canuto/vault/`
3. Settings → Community Plugins → Browse → "Local REST API" → Install → Enable
4. Copie a API key do plugin
5. Rode `install.sh` com `--api-key` ou configure manualmente

Depois disso, nunca mais precisa mexer. Funciona pra todos os projetos.

---

## 8. Dicas

- **"Continue"** ao iniciar retoma de onde parou sem precisar re-explicar.
- **"/office-hours"** antes de features grandes evita retrabalho.
- **"set FAST_MODE"** para quick fixes que nao precisam de Tester.
- **Graph view** no Obsidian mostra como decisions, instincts e sessions se conectam.
- **"health check"** se algo parecer estranho — diagnostica tudo.
- O Maestro **nunca** roda Git ou shell sem pedir confirmacao.
- Instincts com alta confianca influenciam decisoes futuras automaticamente.

---

*Canuto Framework v1.6 — Rodrigo Canuto (c) 2026*
