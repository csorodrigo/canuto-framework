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

## 4. Slash Commands — Referencia Completa

Disponiveis em **qualquer projeto**. Instalados em `~/.claude/skills/`.

### A. Canuto Core (globais)

| Comando | O que faz | O que esperar |
|---------|-----------|---------------|
| `/briefing` | Carrega contexto completo do projeto | Briefing em 5 linhas: ultima sessao, pendentes, alertas, instincts ativos |
| `/commit` | Commit semantico com validacoes | Analisa diff, gera mensagem convencional, pede confirmacao |
| `/fix` | Debug com causa raiz confirmada | Read-only primeiro, diagnostico, propoe fix minimo |
| `/test` | Roda testes do projeto | Detecta framework automaticamente, roda, reporta cobertura e falhas |
| `/review` | Revisao pre-commit | Checa console.logs, tipos TS, imports nao usados, padroes do projeto |
| `/deploy` | Deploy com validacoes completas | Branch → build → testes → health check → smoke test |
| `/deploy-gate` | Checklist pre-deploy | Veredicto binario claro: **PRONTO** ou **BLOQUEADO** |
| `/supabase-migration` | Migration + RLS | Gera SQL → verifica RLS → atualiza tipos TS → documenta |
| `/canuto-init` | Onboarding de projeto novo | Gera `.agents/`, detecta stack, cria CLAUDE.md, inicializa memoria |
| `/termdock-ast` | Busca AST (simbolos, dependencias) | Onde esta X, quem chama X, o que depende de X, impacto de refactor |
| `/xcodebuildmcp-cli` | Build/test iOS/macOS | Build, run, test, debug, logs, UI automation via XcodeBuildMCP |
| `/ios-device-deploy` | Deploy iOS em device fisico | Requer cabo USB, Release config e provisioning profile valido |

### B. Design Impeccable (gstack)

| Comando | O que faz | O que esperar |
|---------|-----------|---------------|
| `/audit` | Scan multi-dimensional de qualidade | Relatorio com score: a11y, performance, responsividade, AI slop patterns |
| `/animate` | Adiciona animacoes e micro-interacoes com proposito | Motion apenas onde agrega — sem decoracao gratuita |
| `/bolder` | Transforma designs genericos em memoraveis | Variantes ousadas com justificativa de cada escolha |
| `/clarify` | Melhora microcopy e textos de interface | Labels, tooltips, mensagens de erro — cada palavra justificada |
| `/colorize` | Introducao estrategica de cor | Paleta 60/30/10 em OKLCH com significado semantico |
| `/critique` | Avaliacao holistica de UX/design | Hierarquia, arquitetura de informacao, emocao, acessibilidade |
| `/harden` | Resiliencia para producao | Edge cases de texto, overflow, i18n, estados vazios, erros |
| `/overdrive` | Interfaces tecnicamente ambiciosas | View Transitions, WebGL, scroll-driven animations, animacoes CSS avanc. |
| `/polish` | Passe final de qualidade | Espacamento, estados hover/focus/disabled, alinhamento, detalhes finais |
| `/typeset` | Auditoria e melhoria de tipografia | Escala, hierarquia, legibilidade, line-height, letra e espacamento |

### C. gstack — Workflow Completo

| Comando | O que faz | O que esperar |
|---------|-----------|---------------|
| `/office-hours` | Reframe de produto estilo YC | 3 abordagens com trade-offs, questiona premissas, salva contexto para Architect |
| `/plan-ceo-review` | Revisao estrategica de plano | Expansao de escopo, foco no problema certo, perspectiva de fundador |
| `/plan-eng-review` | Revisao de arquitetura de plano | Data flow, diagramas, edge cases, cobertura de testes, performance |
| `/plan-design-review` | Revisao de design de plano | Score 0-10 por dimensao, o que precisa para chegar a 10, fix do plano |
| `/autoplan` | Todos os reviews de uma vez | CEO + eng + design reviews automaticos com auto-decisoes, gate final |
| `/codex` | Second opinion adversarial | "200 IQ adversarial dev" testa suas suposicoes e tenta quebrar seu codigo |
| `/design-consultation` | Cria sistema de design completo | Estetica, tipografia, cor, layout, motion → `DESIGN.md` como fonte da verdade |
| `/design-review` | Audit visual com screenshots | Inconsistencias, espacamento, hierarquia, AI slop → fix atomico com evidencia |
| `/qa` | QA completo + fix de bugs | Testa com Chromium real, fix atomico por bug, score saude antes/depois |
| `/qa-only` | QA so relatorio, sem fix | Report estruturado com health score, screenshots, repro steps |
| `/browse` | Headless browser rapido | Screenshot, clicar, preencher, verificar estado — ~100ms por acao |
| `/ship` | Cria PR com bump de versao | Merge base, testes, review diff, bump VERSION, CHANGELOG, push, PR |
| `/land-and-deploy` | Merge + verificar producao | Merge PR → espera CI → verifica saude via canary checks |
| `/canary` | Monitoramento pos-deploy | Assiste console errors, performance, falhas — alerta em anomalias |
| `/benchmark` | Deteccao de regressao de performance | Baseline de load time, Core Web Vitals, bundle size — compara antes/depois |
| `/investigate` | Debugging forense | Iron Law: sem fix sem causa raiz confirmada — fase read-only obrigatoria |
| `/retro` | Retrospectiva semanal | Le metrics.md, audit-log.md, instincts.md → Shipped / Delayed / Learned / Next |
| `/document-release` | Atualiza docs apos ship | README, FEATURE-MAP.md, .context.md, CHANGELOG — zero docs desatualizados |
| `/review` | Code review do diff | Revisao independente com pass/fail gate |
| `/careful` | Guardrails contra operacoes destrutivas | Avisa antes de rm -rf, DROP TABLE, force-push, reset --hard |
| `/guard` | Safety mode maximo | `/careful` + `/freeze` — edit restrictions + warnings destrutivos |
| `/freeze` | Restringe edits a um diretorio | Bloqueia Edit/Write fora do path definido para a sessao |
| `/unfreeze` | Remove restricao de edits | Libera escopo de edicoes para todos os diretorios |
| `/setup-deploy` | Configura deploy automatico | Detecta plataforma (Fly, Vercel, Render...), grava config no CLAUDE.md |
| `/setup-browser-cookies` | Importa cookies do browser real | Picker de dominios, importa sessao autenticada para headless |
| `/loop` | Repete skill em intervalo | Ex: `/loop 5m /qa` — util para monitoramento continuo |
| `/claude-api` | Constroi com Anthropic SDK | Scaffolding, exemplos, patterns do Claude API e Agent SDK |
| `/simplify` | Revisao de qualidade de codigo | Detecta over-engineering, duplicacao, ineficiencias — fix direto |
| `/gstack-upgrade` | Atualiza gstack | Detecta global vs vendored, roda upgrade, mostra o que mudou |

### D. Skills do Projeto (.agents/skills/)

Invocadas automaticamente pelo Maestro, mas voce pode chamar diretamente:

| Skill | O que faz | O que esperar |
|-------|-----------|---------------|
| `health-check` | Saude geral do framework | HEALTHY / DEGRADED / BROKEN + lista itemizada de 112 checks |
| `auto-analysis` | Scan profundo + cross-reference | Gera `project-index.json` e `onboarding-report.md`, cruza com outros projetos no vault |
| `research` | Busca community intelligence | Phase 0 (Reddit/HN/X/YouTube) → codebase → vault → riscos → plano estruturado |
| `browser-qa` | QA com Chrome DevTools | Usa sessao autenticada do browser real — sem re-login, sem CAPTCHA |
| `vault-maintenance` | Manutencao do vault Obsidian | Arquiva sessoes antigas, agrega metricas/audits, limpa snapshots orfaos |
| `skill-creator` | Cria novos skills | Workflow 7-fases para construir e registrar novos playbooks no framework |
| `context-maintenance` | Mantem .context.md atualizado | Detecta mudancas via git diff, regenera contextos desatualizados |
| `continuous-learning` | Extrai e evolui instincts | Captura padroes da sessao, propoe instincts, promove por confianca |
| `experiment-loop` | Loop de experimentos A/B | Define metrica + variavel + teste → N variacoes → mantem melhor → relatorio |
| `knowledge-ingest` | Ingere fontes externas no vault | YouTube, artigos, PDFs, transcripts → claims + frameworks + action items |
| `frontend-design` | Design frontend coerente | Tailwind + shadcn/ui com principios opinionados — resultado visualmente distintivo |
| `adr` | Architecture Decision Records | Cria ADR numerado com contexto, decisao, consequencias |
| `api-design` | Design de APIs | REST/GraphQL best practices, contratos, versionamento |
| `security-practices` | Checklist de segurança | OWASP top 10, RLS, env vars, validacao de inputs, secrets |
| `session-goals` | Define metas da sessao | Coleta ate 3 goals, rastreia status ao longo da sessao |
| `research` | Pesquisa community + vault + code | Contexto completo antes de qualquer decisao arquitetural |
| `squads` | Orquestra multiplos agentes | Divide trabalho entre subagentes paralelos para tarefas grandes |
| `product-review` | Review de produto | Avalia feature sob perspectiva de usuario, negocio e tecnica |
| `plan-second-opinion` | Segunda opiniao em planos | Avalia plano de angulo diferente, aponta riscos e alternativas |

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

## 13. Workflows por Cenario

### Fluxo: Seguranca

Use quando suspeitar de vulnerabilidade, implementar autenticacao, lidar com dados sensiveis, ou antes de expor qualquer endpoint publico.

```
1. /research          → Busca community intelligence (CVEs, pitfalls, solucoes conhecidas)
2. /investigate       → Diagnostico forense — Iron Law: sem fix sem causa raiz confirmada
3. /careful           → Ativa guardrails contra operacoes destrutivas
4. Architect planeja  → Com skill security-practices como constraint obrigatorio
5. Coder implementa   → Minimal footprint: nada alem do necessario
6. /review            → Code review focado em OWASP top 10, injection, auth, secrets
7. /qa                → Testa edge cases com browser real (auth bypass, XSS, inputs maliciosos)
8. /deploy-gate       → Verifica env vars, RLS, secrets antes de subir
9. /canary            → Monitora pos-deploy por comportamentos anomalos
```

**Quando pular passos:** Para fixes de segurança urgentes em prod, va direto para `/investigate` → `/careful` → Coder → `/deploy-gate`. Documente depois.

---

### Fluxo: Melhorar Frontend

Use quando o frontend estiver funcionando mas parecer generico, inconsistente, ou "feito por IA". Tambem util antes de demos ou launches.

```
1. /browse            → Screenshots baseline — documenta o estado atual (antes)
2. /audit             → Scan: a11y, performance, responsividade, AI slop patterns — score inicial
3. /critique          → Avaliacao holistica: hierarquia visual, arquitetura de informacao, emocao
4. /design-review     → Designer's eye: inconsistencias, espacamento errado, alinhamento quebrado
5. /colorize          → Paletas estrategicas 60/30/10 OKLCH com significado semantico
6. /typeset           → Tipografia: escala, hierarquia, legibilidade, line-height
7. /clarify           → Microcopy: labels, tooltips, mensagens de erro — cada palavra justificada
8. /harden            → Edge cases: overflow de texto, i18n, estados vazios, erros de rede
9. /animate           → Micro-interacoes com proposito — transicoes, feedback, loading states
10. /polish           → Passe final: espacamento, estados hover/focus/disabled, detalhes finais
11. /browse           → Screenshots depois — compare com baseline do passo 1
```

**Dica:** Voce nao precisa rodar todos. `/audit` → `/design-review` → `/polish` ja resolve 80% dos casos. Use os outros para launches importantes.

---

### Fluxo: Problema Muito Complexo

Use quando o problema for ambiguo, envolver multiplos sistemas, ter muitos stakeholders, ou quando a abordagem certa nao for obvia.

```
1. /office-hours      → YC-style: reframe o problema, 3 abordagens, questiona premissas — antes de qualquer codigo
2. /research          → Community intelligence: como outros resolveram isso + vault + codebase + riscos
3. /plan-ceo-review   → Revisao estrategica: e o escopo certo? e o problema certo a resolver?
4. /plan-eng-review   → Revisao de arquitetura: data flow, edge cases, diagramas, performance
5. /autoplan          → Roda CEO + eng + design review de uma vez com auto-decisoes — gate final para voce aprovar
6. /codex             → Second opinion adversarial: tenta quebrar suas suposicoes antes de implementar
7. /careful           → Safety mode se tocar producao, banco de dados ou dados de usuario
8. Architect planeja  → Com todos os reviews e constraints como input — plano solido
9. Coder implementa   → Incrementalmente, uma camada por vez — feature flags se necessario
10. /qa               → QA exaustivo com browser real: happy path + edge cases + regressoes
11. /canary           → Monitoramento pos-deploy: console errors, performance, anomalias
12. /document-release → Atualiza README, FEATURE-MAP.md, .context.md, CHANGELOG
13. /retro            → Retrospectiva para capturar aprendizados como instincts no vault
```

**Quando pular passos:** Para problemas complexos mas bem definidos, pule `/office-hours` e va direto para `/research` → `/plan-eng-review` → Architect. Use `/autoplan` quando quiser as tres perspectivas (CEO, eng, design) sem ter que responder 30 perguntas manualmente.

---

*Canuto Framework v1.8 — Rodrigo Canuto (c) 2026*
