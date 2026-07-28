# Troubleshooting — Canuto Framework

Guia de solução de problemas comuns.

---

## Problemas de Instalação

| Problema | Causa | Solução |
|----------|-------|---------|
| `install.sh` falha com "python3 not found" | Python 3 não instalado | `brew install python3` (macOS) ou `apt install python3` (Linux) |
| `install.sh` falha com "jq not found" | jq não instalado | `brew install jq` (macOS) ou `apt install jq` (Linux) |
| Canvas não gera após install | python3 indisponível ou vault path com espaços | Verifique `python3 --version`. Evite espaços no caminho do vault |
| Permissão negada nos hooks | Hooks não são executáveis | `chmod +x .agents/hooks/*.sh` |

## Problemas com Obsidian / MCP

| Problema | Causa | Solução |
|----------|-------|---------|
| "MCP tools not available" | Obsidian não está rodando ou Local REST API desabilitado | 1. Abra Obsidian. 2. Ative o plugin "Local REST API" (Community Plugins). 3. Copie a API key |
| "Vault not found" no session start | Vault não foi criado ou path errado | Rode `bash install.sh` para criar. Verifique `~/.canuto/vault/` |
| MCP conecta mas notas não aparecem | Vault aberto no Obsidian é diferente do vault do Canuto | No Obsidian: File → Open folder as vault → selecione `~/.canuto/vault/` |
| "API key invalid" | API key do Local REST API mudou | Copie a nova key de Settings → Local REST API → Copy API Key. Atualize em `.agents/mcp/server.json` |
| Obsidian crashou durante sessão | Crash ou fechamento acidental | O Canuto entra em modo offline. Dados ficam em `.agents/.cache/pending-sync/`. Na próxima sessão, rode `/vault-sync` |

## Problemas de Sessão

| Problema | Causa | Solução |
|----------|-------|---------|
| Session briefing vazio | Vault sem dados (primeiro uso) | Normal na primeira sessão. O briefing popula após a primeira sessão completa |
| "Not a Canuto project" | Vault não tem diretório para este projeto | Rode `bash install.sh` no diretório do projeto |
| Instincts não aparecem no briefing | Todos os instincts têm confidence `low` | O briefing mostra `high` e `medium`. Use `/instincts` para ver todos |
| Stale context warnings | Código mudou mas `.context.md` não foi atualizado | Peça ao Contextualizer: "atualize os contextos stale" |
| Sessão anterior não carrega | Session note não foi salva | Verifique `~/.canuto/vault/projects/{slug}/sessions/`. Se vazio, dados foram perdidos |

## Monorepos e Workspaces

| Problema | Causa | Solução |
|----------|-------|---------|
| Dois projetos com mesmo slug | `basename` do diretório é igual (ex: dois `app/`) | Adicione `project-slug: nome-unico` no CLAUDE.md de cada projeto |
| Vault mistura dados de projetos | Slug conflitante | Use override de slug (veja acima) |

### Configurar slug personalizado

No `CLAUDE.md` do projeto:

```markdown
## Project Rules
- project-slug: meu-monorepo-frontend
```

O Maestro e os hooks respeitam esse override em vez de usar `basename`.

## Problemas com Hooks

| Problema | Causa | Solução |
|----------|-------|---------|
| Hooks não rodam | Hooks não instalados em `~/.claude/hooks/` | Rode `bash install.sh --update` para reinstalar |
| Hook roda mas não mostra output | Output está sendo capturado/suprimido | Verifique se o hook usa `echo` (stdout) e não `>&2` (stderr) |

## Problemas com Bases (Obsidian)

| Problema | Causa | Solução |
|----------|-------|---------|
| Base vazia no Obsidian | Nenhuma nota com frontmatter matching | Normal antes de acumular sessões. Bases populam automaticamente |
| Base mostra "Query error" | Sintaxe do Dataview incorreta | Verifique `.agents/vault/bases/`. Rode `bash test-framework.sh` para validar |
| Base não atualiza | Cache do Dataview | No Obsidian: Ctrl/Cmd+P → "Reload app without saving" |

## Problemas com analyze.sh

| Problema | Causa | Solução |
|----------|-------|---------|
| "No vault found" | Vault não existe | Rode `bash install.sh` primeiro |
| "python3 required" | Python 3 não instalado | Instale python3 |
| Report vazio | Nenhum projeto no vault | Use o framework por pelo menos 1 sessão primeiro |

## Comandos Úteis de Diagnóstico

```bash
# Verificar saúde do framework
bash test-framework.sh --verbose

# Analisar vault cross-project
bash analyze.sh

# Verificar vault existe
ls -la ~/.canuto/vault/

# Listar projetos no vault
ls ~/.canuto/vault/projects/

# Verificar hooks instalados
ls -la ~/.claude/hooks/

# Testar syntax dos hooks
```
