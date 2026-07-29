# ADR-0008 — Hook é código síncrono no caminho crítico: nada espera para sempre

Data: 2026-07-29 · Status: aceito

## Contexto

O Codex CLI passou a demorar dezenas de segundos para abrir, "como se tivesse
algo travado em deadlock". Não era deadlock: era o framework.

Um hook não é um script auxiliar que roda em paralelo. Ele é **código síncrono
no caminho crítico do runtime** — o Claude Code ou o Codex CLI ficam parados até
o hook retornar. Isso significa que qualquer espera não limitada dentro de um
hook vira uma trava do produto inteiro, sem log, sem erro e sem sintoma que
aponte para o hook.

Três defeitos independentes da mesma família estavam em pé, todos invisíveis
porque nenhum deles produz mensagem de erro:

1. **Leitura de stdin sem guarda de TTY.** Catorze hooks faziam `INPUT=$(cat)`.
   Quando stdin é um terminal em vez de um pipe, `cat` espera input para
   sempre. Medido: hooks presos indefinidamente contra um pty; depois da guarda,
   20 ms.

   A variante que quase passou despercebida não usa `cat`: `cmd=$(jq -r '...')`
   sem operando de arquivo também lê stdin. Estava em `log-commands.sh` e
   `protect-files.sh` — que rodam a **cada** comando Bash e a **cada** edição de
   arquivo.

2. **Timeout que não mata o filho.** O `session-start.sh` anunciava
   "4s soft timeout via perl alarm". O alarme só fazia o `perl` sair; o processo
   filho seguia vivo e o fechamento implícito do pipe esperava por ele. Medido
   contra um health check de 30s: 4s prometidos, **31s reais**. E o health check
   é caro de verdade — ele dispara `codex mcp list`, `codex mcp get` por
   servidor, `brew/npm/uvx/gh --version`, nenhum com limite próprio.

3. **`timeout` que não existe.** macOS não traz o `timeout` do GNU; com o
   coreutils do brew ele chega como `gtimeout`. Todo ponto que chamava `timeout`
   direto virava no-op silencioso (`rc=127`) justamente na máquina onde o
   problema aparecia. O `heartbeat-run.sh` morria assim a cada execução, com
   cara de "rodou e não achou nada".

O agravante do conjunto: o `codex-pretool-guard.sh` sobe um **segundo `codex
exec` completo** de dentro de um hook do Codex, e o tier `fast` — o que deveria
ser o barato — era o único sem limite de tempo. O caminho `full` já usava
`codex_run_with_timeout` desde sempre.

## Decisão

Três regras mecânicas, verificadas por teste:

1. **Todo hook que lê stdin guarda com `[ -t 0 ]`.** Sem stdin de verdade não há
   payload a processar; o hook segue sem ele em vez de esperar. Vale para `cat`,
   para `jq` sem arquivo e para laços `while read` sem redirecionamento.

2. **Todo timeout mata o filho, e o grupo dele.** Matar só o filho direto deixa
   os netos (`codex`, `brew`) segurando o pipe e o `read` bloqueado. Ordem de
   preferência: `timeout` → `gtimeout` → `perl` com `setpgrp` +
   `kill("KILL", -$pid)` → **pular a tarefa**. Perder duas linhas de diagnóstico
   é barato; travar a abertura da sessão não é.

3. **Nenhum ponto assume `timeout`.** Onde não há fallback, o macOS fica
   descoberto — e é a plataforma principal.

## Consequências

O `Test 13` do `test-framework.sh` verifica as três regras estaticamente e falha
o build se um hook regredir.

A checagem é **estática de propósito**. A primeira versão executava cada hook
num pty real — foi ela que achou o bug —, mas se auto-envenena: o
`require-tests-for-pr.sh` roda o `test-framework.sh`, que rodaria o probe, que
rodaria o gate outra vez. Recursão infinita. O probe dinâmico continua útil para
investigação manual, só não pode viver dentro da suíte que ele executa.

Custo aceito: a checagem estática reconhece padrões, não semântica. Uma forma
nova de ler stdin (um `read` embutido em função, um `python3 -` sem arquivo)
passa batido até alguém ensiná-la. É menos garantia que a execução real, e é o
preço de não ter recursão.
