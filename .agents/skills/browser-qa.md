shortDescription: Quando e como usar /qa + /browse do gstack no fluxo de QA — browser real vs testes unitários, pré-requisitos, integração com coverage-tracking.
usedBy: [tester, maestro]
version: 1.1.0
lastUpdated: 2026-03-23
copyright: Rodrigo Canuto © 2026.
evals:
  - prompt: "the login flow and checkout form need browser testing before we ship"
    should_trigger: true
  - prompt: "implemented a new modal, test that it opens and closes correctly in the browser"
    should_trigger: true
  - prompt: "write unit tests for the checkout form component"
    should_trigger: false
  - prompt: "take a screenshot of the current state of the dashboard page"
    should_trigger: false

## When to Use

**Triggers:**
- Feature com interface de usuário (formulários, fluxos de navegação, modais)
- Task de checkout, autenticação, onboarding — fluxos críticos de usuário
- Bug relatado em "funciona no código mas quebra na tela"
- Regression testing de releases com mudanças de UI

**Not for:**
- Lógica de negócio sem UI (use Tester persona)
- APIs e integrações backend (use Tester + integration tests)
- Projetos sem frontend web
- Quando gstack não está instalado (verifique antes de invocar)

---

## Purpose

O Tester persona do Canuto escreve e executa testes unitários/integração. Isso cobre a lógica, mas não testa **o que o usuário realmente vê e clica**. O browser QA via gstack usa Chromium real para:

- Navegar pela aplicação como um usuário real
- Clicar em botões, preencher formulários, seguir fluxos
- Detectar erros visuais, quebras de layout, states incorretos
- Gerar regression tests para cada bug encontrado

---

## Divisão de Responsabilidade

| Tipo de teste | Quem faz | Quando |
|---|---|---|
| Unitários e integração | Tester persona | Sempre — obrigatório |
| QA de fluxo de usuário | /qa (gstack) | Features com UI em tasks M/L |
| Automação pontual de browser | /browse (gstack) | Quando precisar clicar/navegar como humano |
| Report sem corrigir | /qa-only (gstack) | Quando quiser identificar bugs sem tocar no código |

---

## Pré-requisitos

Antes de invocar `/qa` ou `/browse`, verifique:

1. **gstack instalado**: `ls ~/.claude/skills/ | grep gstack` deve retornar resultado
2. **Bun instalado**: `bun --version` deve funcionar (necessário para o binary do /browse)
3. **App rodando localmente**: o `/qa` precisa de uma URL acessível (ex: `http://localhost:3000`)
4. **Tester já rodou**: os testes unitários devem ter passado antes do browser QA

Se algum pré-requisito falhar: informe o usuário com instrução de correção.

---

## Protocolo do Tester/Maestro

### Quando Tester Deve Sugerir Browser QA

Após rodar os testes unitários/integração:

```
"Testes de código: ✅ passando.
Esta feature tem UI (formulário de login, fluxo de checkout, etc.).
Recomendo rodar /qa para validar no browser real. Quer prosseguir?"
```

### Como Informar o gstack

Ao invocar `/qa`, forneça contexto:

```
"Rode /qa no fluxo de {nome do fluxo} em http://localhost:{porta}.
Foque em: {o que deve ser testado}.
Corrija bugs encontrados com commits atômicos e gere regression tests."
```

### Após o Browser QA

1. Verifique os regression tests gerados pelo `/qa` — eles devem ser adicionados ao repositório
2. Atualize `coverage-tracking.md` registrando cobertura de QA visual:
   ```
   [browser-qa] {data}: fluxo {nome} testado em {porta} — {N bugs encontrados, X corrigidos}
   ```
3. Se bugs críticos foram encontrados: registre em `audit-log.md` como evento de qualidade

---

## /browse — Uso Pontual

O `/browse` oferece ~100 subcomandos para automação de browser. Use quando precisar de controle granular:

- **Scraping de dados**: navegar e extrair informações de uma página
- **Reprodução de bug**: simular exatamente os passos que causam um erro
- **Teste de autenticação**: fazer login em um fluxo real para testar páginas protegidas
- **Setup de cookies**: use `/setup-browser-cookies` para importar sessão do Chrome/Arc/Brave

Exemplos de uso:
```
/browse navigate http://localhost:3000/login
/browse fill [form] email: user@test.com, password: test123
/browse click [button] "Entrar"
/browse screenshot
```

---

## Authenticated Data Extraction (Optional)

### Chrome DevTools MCP

Chrome shipped a feature that lets AI agents use a browser you're already logged into. No re-login, no API, no CAPTCHA workaround. The agent reuses the session you already have open — Gmail, X, Notion, Stripe, internal tools, everything.

**Use cases:**
- Extract data from analytics dashboards (Google Analytics, Mixpanel, etc.)
- Scrape CRM data (HubSpot, Salesforce admin)
- Pull reports from SaaS tools behind login walls
- Extract data from internal admin panels
- Sync new Notion tasks to Slack
- Pull traffic source data from Google Analytics
- Extract low-engagement posts from X
- Flag unprocessed refunds in Stripe

**Prerequisites:**
1. Update Chrome to the latest version
2. Open `chrome://inspect/#remote-debugging` in Chrome
3. Check the "Allow remote debugging for this browser instance" checkbox
4. Server will be active at `127.0.0.1:9222`

**MCP Configuration (Option 1 — Chrome DevTools MCP):**
```json
{
  "mcpServers": {
    "chrome-devtools": {
      "command": "npx",
      "args": ["chrome-devtools-mcp@latest", "--channel", "stable", "--autoConnect"]
    }
  }
}
```

The `--autoConnect` flag connects automatically to the Chrome instance you already have running and reuses your current logged-in session. No environment variables needed.

**Alternative (Option 2 — browser-use CLI 2.0):**
```bash
browser-use --connect
```

The `--connect` flag reuses the session you already have open instead of launching a new browser. Direct CDP underneath.

**How it works:**
1. User opens Chrome normally, enables remote debugging, and logs into the target site
2. `--autoConnect` connects the agent to the existing browser session automatically
3. Agent navigates, extracts data, takes screenshots — all using the user's auth
4. Extracted data can be fed into `knowledge-ingest` skill for structured vault notes

**Guardrails:**
- Always inform the user before navigating to any page — the agent is using THEIR session
- Never submit forms or click "delete"/"confirm" buttons without explicit user approval
- Use for READ operations only (data extraction, not actions)
- When done: uncheck "Allow remote debugging" in `chrome://inspect/#remote-debugging`

> [!warning] Chrome DevTools MCP gives the agent full access to your authenticated browser session (saved data, cookies, site data, ability to navigate to any URL). Only enable remote debugging when actively extracting data, and disable it when done.

---

## Relacionamentos com Outros Skills

- **Tester persona** → roda primeiro; /qa é complementar, não substituto
- **coverage-tracking.md** → registre cobertura de browser QA
- **audit-log.md** → bugs críticos de browser QA devem ser logados
- **gstack /careful** → ative antes do /qa em ambientes de staging (proteção contra deleção acidental)
- **knowledge-ingest** → dados extraídos via Chrome DevTools MCP podem ser ingeridos como vault notes
- **defuddle** → para páginas públicas, prefira `defuddle` (mais simples, sem browser necessário)

---

## Gemini multimodal integration

Este skill analisa screenshots ou consome mídia visual. Use **Gemini 3.1-pro-preview**
como analisador visual primário — OCR + layout understanding são superiores ao que
Claude isolado faz com imagens (POC 2026-04-17 validou coerência).

```
# 1. Capture via /browse, /gstack ou Playwright (Codex) — nunca screencapture
#    automático sem mask (risco PII — ver gemini-routing.md)
# 2. Copie a imagem pra dentro do workspace (gemini-cli bloqueia /tmp)
cp /path/to/shot.png .context/shot.png

# 3. Analise via Gemini multimodal
mcp__gemini__ask-gemini({
  prompt: "@.context/shot.png [análise específica — a11y, spacing, hierarquia,
           overflow, etc.]. Output em markdown estruturado.",
  model: "gemini-3.1-pro-preview"
})

# 4. Delete imediatamente
rm .context/shot.png
```

Gemini faz **ver** (OCR objetivo). Claude Opus faz **julgar** (taste).
Ver `.agents/skills/gemini-routing.md` pros gotchas.
