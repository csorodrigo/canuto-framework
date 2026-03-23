# Canuto Framework — Tutorial Completo

## 1. Iniciando uma Sessao

Abra o Claude no diretorio do seu projeto. O Maestro automaticamente:

1. Determina o projeto pelo nome da pasta (ou pelo nome do projeto no Conductor: `workspaces/{projeto}/{branch}`)
2. Carrega a memoria do vault (`~/.canuto/vault/projects/{projeto}/`)
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
| `/research` | Analise estruturada: community intelligence + codebase + vault → analisa riscos → gera plano. |
| `/auto-analysis` | Scan profundo do projeto + cross-reference com outros projetos no vault. |
| `/vault-maintenance` | Limpeza periodica: arquiva sessoes antigas, agrega metricas/audits, limpa snapshots. |

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
| `all-instincts.base` | Todos os instincts de todos os projetos |
| `global-instincts.base` | Instincts globais (compartilhados entre projetos) |
| `decisions-timeline.base` | Timeline de decisoes |
| `pending-tasks.base` | Tasks pendentes |
| `audit-by-type.base` | Eventos de audit por tipo |
| `metrics-dashboard.base` | Dashboard de metricas |
| `all-metrics.base` | Metricas de todos os projetos |
| `components-registry.base` | Registro de componentes UI |
| `cross-project-patterns.base` | Padroes compartilhados entre projetos |

---

## 7. Instalacao e Migracao — Referencia Rapida

```bash
# ── Fresh install (projeto novo) ──
curl -fsSL https://raw.githubusercontent.com/csorodrigo/canuto-framework/main/install.sh | bash

# ── Atualizar framework (ja instalado, nao toca vault/plugins) ──
curl -fsSL https://raw.githubusercontent.com/csorodrigo/canuto-framework/main/install.sh | bash -s -- --update

# ── Migrar de v1.5 para v1.6 (UMA VEZ so, converte flat-file → Obsidian) ──
curl -fsSL https://raw.githubusercontent.com/csorodrigo/canuto-framework/main/install.sh | bash -s -- --migrate --api-key SUA_KEY

# ── Instalar skill opcional ──
bash install.sh --skill adr --skill session-goals

# ── Checar versoes e integridade ──
bash install.sh --check
```

> **update vs migrate:** Use `--update` para atualizar personas, skills e hooks para a versao mais recente.
> Use `--migrate` apenas uma vez, quando estiver saindo da v1.5 (flat-file) para a v1.6 (Obsidian vault).
> Se ja esta na v1.6, `--migrate` nao e necessario — use `--update`.

### Setup unico do Obsidian

1. Instale o Obsidian: [obsidian.md](https://obsidian.md)
2. File → Open folder as vault → `~/.canuto/vault/`
3. Settings → Community Plugins → Browse → "Local REST API" → Install → Enable
4. Copie a API key do plugin
5. Rode `install.sh` com `--api-key` ou configure manualmente

Depois disso, nunca mais precisa mexer. Funciona pra todos os projetos.

---

## 8. Monorepos e Workspaces

Se voce trabalha com monorepos (yarn workspaces, pnpm, npm workspaces), pode ter conflito de slugs — dois pacotes com o mesmo `basename` (ex: `packages/app` e `services/app`).

### Solucao: Override de slug

No `CLAUDE.md` de cada pacote, defina um slug unico:

```markdown
## Project Rules
- project-slug: monorepo-frontend-app
```

O Maestro e os hooks usam esse slug em vez de `basename` do diretorio.

### Como funciona

- Cada pacote do monorepo tem seu proprio vault: `~/.canuto/vault/projects/monorepo-frontend-app/`
- Sessions, instincts, decisions — tudo separado por pacote
- Instincts globais (`global-instincts/`) sao compartilhados entre todos

### Dica

Use `bash analyze.sh` para ver todos os projetos do vault de uma vez — util para monorepos com muitos pacotes.

---

## 9. Validacao e CI

### Hooks de validacao do vault

Dois hooks verificam a saude do vault automaticamente:

```bash
# Detectar wikilinks e links quebrados
bash .agents/hooks/check-references.sh

# So arquivos modificados (mais rapido)
bash .agents/hooks/check-references.sh --changed-only

# Detectar notas orfas, frontmatter vazio, metricas faltando
bash .agents/hooks/check-orphans.sh

# Verificar vault especifico
bash .agents/hooks/check-orphans.sh --vault ~/.canuto/vault
```

**Quando rodar:**
- Apos migrations (`install.sh --migrate`)
- Apos mudancas estruturais no vault
- O Maestro sugere automaticamente no briefing se arquivos do vault mudaram

### CI com GitHub Actions

O framework inclui `.github/workflows/validate-framework.yml` que roda em PRs para `main`:

1. Syntax check em todos os `.sh`
2. Validacao de frontmatter das skills
3. `test-framework.sh --verbose` (estrutura completa)
4. `install.sh --check` (integridade)
5. `check-references.sh` e `check-orphans.sh` (vault, non-blocking)

### Headless Mode (scripts em CI)

Scripts do framework precisam funcionar sem terminal interativo. A regra:

```bash
if [[ -t 0 ]]; then
  # Terminal interativo — pode perguntar ao usuario
  read -p "API key: " key
else
  # CI / pipe — usar flag ou env var
  key="${OBSIDIAN_API_KEY:-}"
fi
```

**Dica:** Teste seus scripts localmente com `< /dev/null` antes de confiar no CI:
```bash
bash install.sh --check < /dev/null
bash test-framework.sh < /dev/null
```

---

## 10. Troubleshooting

Se algo nao funcionar, consulte `docs/TROUBLESHOOTING.md` para solucoes de problemas comuns:

- Obsidian/MCP nao conecta
- Briefing vazio ou sessao sem memoria
- Hooks nao rodam
- Bases vazias no Obsidian

Ou rode o diagnostico: `bash test-framework.sh --verbose`

---

## 11. Novas Capabilities

### Knowledge Ingestion

Ingira fontes externas no vault como notas estruturadas:

```
"Ingest this YouTube video: https://youtube.com/watch?v=abc123"
"Process this meeting transcript: /path/to/standup.txt"
"Clip this article: https://example.com/article"
```

O skill `knowledge-ingest` aceita: YouTube, artigos web, PDFs, audio/video, e meeting transcripts. Extrai claims, frameworks, action items e salva em `vault/knowledge/ingested/`.

### Community Research

O skill `research` agora tem Phase 0 (Community Intelligence). Antes de investigar o codebase, busca em paralelo no Reddit, HN, X, YouTube e Stack Overflow:

```
"Research Playwright vs Cypress"
→ Busca community threads, consolida consenso, pitfalls, e controversias
→ Depois investiga codebase + vault como antes
```

Ferramenta opcional para research mais profunda: [/last30days](https://github.com/mvanhorn/last30days-skill) (instalar separadamente).

### Experiment Loop

Otimizacao automatica com o padrao Karpathy — change, test, measure, keep/discard, repeat:

```
"Optimize Vite build time"
→ Define metrica (build time) + variavel (vite config) + teste (time npx vite build)
→ Roda N variacoes, mantem a melhor, apresenta relatorio
```

### Chrome DevTools MCP (Scraping Autenticado)

Extraia dados de sites onde voce ja esta logado (dashboards, CRM, admin panels):

1. Abra `chrome://inspect/#remote-debugging` e marque "Allow remote debugging"
2. Configure o MCP: `chrome-devtools-mcp@latest --autoConnect`
3. O agente usa sua sessao autenticada — sem re-login, sem CAPTCHA

Veja detalhes no skill `browser-qa.md`.

### Voice Input

Voice-to-text funciona bem com Claude Code — typos e frases incompletas sao interpretados pelo contexto. Ferramentas: [Monologue](https://usemonologue.com) ou WhisperFlow.

---

## 12. Dicas

- **"Continue"** ao iniciar retoma de onde parou sem precisar re-explicar.
- **"/office-hours"** antes de features grandes evita retrabalho.
- **"/research"** para investigar antes de planejar — consulta comunidade + vault + codebase e gera plano estruturado.
- **"/auto-analysis"** ao onboardar um projeto — gera index e cross-referencia com outros projetos.
- **"/vault-maintenance"** periodicamente para arquivar sessoes velhas e agregar metricas.
- **"set FAST_MODE"** para quick fixes que nao precisam de Tester.
- **Graph view** no Obsidian mostra como decisions, instincts e sessions se conectam.
- **"health check"** se algo parecer estranho — diagnostica tudo.
- O Maestro **nunca** roda Git ou shell sem pedir confirmacao.
- Instincts com alta confianca influenciam decisoes futuras automaticamente.
- Apos migrations, rode `check-orphans.sh` para garantir integridade do vault.
- Nunca pushe direto ao main — use feature branch + PR. O CI valida tudo automaticamente.
- Use `bash migrate-slug.sh <old> <new>` se precisar renomear um projeto no vault.

### Workflow recomendado para features grandes

```
1. /office-hours        → Entender o problema antes de codar
2. /research            → Community intelligence + codebase + vault + riscos
3. Architect planeja    → Maestro delega automaticamente
4. Coder implementa    → Com testes
5. Tester valida       → Edge cases + regressoes
6. Reviewer aprova     → Checklist de qualidade
7. /document-release   → Atualiza docs
8. Maestro encerra     → Salva tudo no vault
```

---

*Canuto Framework v1.7 — Rodrigo Canuto (c) 2026*
