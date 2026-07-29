# ADR-0009 — Dependência emprestada é calendário de release emprestado

Data: 2026-07-29 · Status: aceito

## Contexto

Os dois MCPs de back-delegation Codex→Claude pararam de subir. O Codex reportava:

```
MCP client for `claude-architect` failed to start: handshaking with MCP server
failed: connection closed: initialize response
```

Ninguém tinha tocado nos arquivos. O último commit em `claude-agent-mcp.py` era
de dias antes e não mexia no import.

O launcher era:

```bash
exec uvx --from codex-as-mcp python "$HOME/.claude/scripts/claude-agent-mcp.py" ...
```

Isso não usa **uma linha** de código do `codex-as-mcp`. O pacote entrava só como
doador de dependência: ele tem `mcp` no virtualenv dele, e a gente pegava carona.

O `codex-as-mcp` pede `mcp[cli]>=1.12.4` — **sem teto**. Quando o `mcp` 2.0.0
saiu, o resolvedor pegou o 2.0.0, e o 2.0.0 removeu `mcp.server.fastmcp` (a API
virou `MCPServer` em `mcp.server.mcpserver`). O import da linha 14 morria com
`ModuleNotFoundError`, o processo saía com `rc=1` antes de responder o
`initialize`, e o cliente via a conexão fechar na cara dele.

Reproduzido em 30 segundos, uma vez que se olhou para o processo em vez de para
a mensagem:

```
$ uvx --from codex-as-mcp python claude-agent-mcp.py --server-name x --mode architect
ModuleNotFoundError: No module named 'mcp.server.fastmcp'
=== EXIT: 1 ===
```

O que atrapalhou o diagnóstico foi a mensagem do cliente. `connection closed:
initialize response` descreve o que o **cliente** observou, não o que o servidor
sofreu — e não aponta para lugar nenhum. Antes dela o mesmo defeito já tinha
usado duas outras máscaras (`No such file or directory` quando o wrapper não
existia, `timed out after 30 seconds` quando o cache do uv estava frio). Três
sintomas, três causas de verdade diferentes, todas no mesmo ponto do arranque.

Agravante: o instalador conferia que o wrapper existia e era executável, e
parava aí. "Wrapper existe" não é "servidor sobe" — a mesma distinção que o
ADR-0008 já tinha aprendido para `codex mcp add` retornar 0 sem validar caminho.
O instalador rodou limpo, com ✅ nos dois servidores, enquanto os dois estavam
mortos.

## Decisão

1. **Todo script declara a própria dependência, com teto.** Cabeçalho PEP 723 no
   `claude-agent-mcp.py` (`mcp[cli]>=1.12.4,<2`), executado por
   `uv run --script`. O teto é o ponto: `>=` sozinho é um convite aberto para o
   próximo major entrar sem ninguém pedir.

2. **Nenhum launcher empresta o virtualenv de terceiro.** `uvx --from <pacote>
   python nosso_script.py` acopla nosso arranque ao calendário de release de um
   projeto que não controlamos e cujo código não usamos.

3. **O instalador prova que o servidor sobe antes de registrar.**
   `uv run --script ... --help` exercita o import (topo do módulo roda antes do
   argparse) e sai 0 sem falar stdio. Import quebrado ⇒ `rc≠0` no instalador, em
   vez de na abertura do Codex. Se falhar, **não registra** — registro que falha
   custa startup em toda sessão, então não registrar é melhor que registrar
   errado.

Sem custo de partida: medido na mesma máquina, com cache quente, `uv run
--script` leva **815ms** contra **1287ms** do `uvx --from`. O conserto é mais
rápido que o defeito.

## Consequências

`Test 14` do `test-framework.sh` verifica as duas primeiras regras
estaticamente, sem rede. Testado por mutação — as três formas quebradas (dep sem
teto, cabeçalho ausente, `uvx --from` de volta) fazem a suíte falhar.

Ficamos em `mcp 1.x` de propósito. Portar para a API 2.x mexe nos decoradores de
tool e no `Context`, e é trabalho que merece ser feito com calma — não se faz
porta de API para apagar incêndio. O teto documenta a dívida em código
executável em vez de num TODO.

Custo aceito: o teto precisa ser levantado à mão quando a porta for feita.
É o preço de não ser atualizado por terceiros sem aviso.
