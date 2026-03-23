shortDescription: Quando e como usar /qa + /browse do gstack no fluxo de QA — browser real vs testes unitários, pré-requisitos, integração com coverage-tracking.
usedBy: [tester, maestro]
version: 1.0.0
lastUpdated: 2026-03-20
copyright: Rodrigo Canuto © 2026.

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

For scraping data from **authenticated** pages (dashboards, admin panels, CRM, analytics tools), use Chrome DevTools MCP. This lets the agent use a browser session you're already logged into — skipping CAPTCHA, 2FA, and re-login flows.

**Use cases:**
- Extract data from analytics dashboards (Google Analytics, Mixpanel, etc.)
- Scrape CRM data (HubSpot, Salesforce admin)
- Pull reports from SaaS tools behind login walls
- Extract data from internal admin panels

**Prerequisites:**
1. Chrome/Chromium running with remote debugging enabled:
   ```bash
   # macOS
   /Applications/Google\ Chrome.app/Contents/MacOS/Google\ Chrome --remote-debugging-port=9222

   # Linux
   google-chrome --remote-debugging-port=9222
   ```
2. Chrome DevTools MCP configured

**MCP Configuration:**
```json
{
  "mcpServers": {
    "chrome-devtools": {
      "command": "npx",
      "args": ["-y", "@anthropic/mcp-chrome-devtools"],
      "env": {
        "CHROME_DEBUG_PORT": "9222"
      }
    }
  }
}
```

**How it works:**
1. User opens Chrome normally and logs into the target site
2. Agent connects to the existing browser session via DevTools Protocol
3. Agent navigates, extracts data, takes screenshots — all using the user's auth
4. Extracted data can be fed into `knowledge-ingest` skill for structured vault notes

**Guardrails:**
- Always inform the user before navigating to any page — the agent is using THEIR session
- Never submit forms or click "delete"/"confirm" buttons without explicit user approval
- Use for READ operations only (data extraction, not actions)
- Close the debugging port when done: the agent should remind the user

> [!warning] Chrome DevTools MCP gives the agent access to your authenticated browser session. Only enable it when actively extracting data, and disable remote debugging when done.

---

## Relacionamentos com Outros Skills

- **Tester persona** → roda primeiro; /qa é complementar, não substituto
- **coverage-tracking.md** → registre cobertura de browser QA
- **audit-log.md** → bugs críticos de browser QA devem ser logados
- **gstack /careful** → ative antes do /qa em ambientes de staging (proteção contra deleção acidental)
- **knowledge-ingest** → dados extraídos via Chrome DevTools MCP podem ser ingeridos como vault notes
- **defuddle** → para páginas públicas, prefira `defuddle` (mais simples, sem browser necessário)
