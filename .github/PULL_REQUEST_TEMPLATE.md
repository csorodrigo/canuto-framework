## O que muda

<!-- O efeito, não a lista de arquivos. Se corrige um defeito, diga o que estava
     errado e por quê — o mecanismo, não só o sintoma. -->

## Validação

<!-- Comandos rodados e resultado real. Número de testes, exit code, onde rodou.
     "Testes passando" sem o comando não é validação, é adjetivo. -->

## O que este PR NÃO prova

<!-- SEÇÃO OBRIGATÓRIA. Preencher sempre — inclusive para escrever
     "nada: a validação cobre todo o escopo", quando for verdade.

     Existe porque apareceu espontaneamente nos melhores PRs deste fluxo
     (mecesa#87, lucrando-ai#2369) e é o que separa entrega honesta de entrega
     vendida. Exemplos reais do que entra aqui:

       • "Nenhum cenário rodou contra o banco real nem num navegador.
          Não chamo isso de validado."
       • "O vermelho era swap — suspeita, não prova: o contra-teste que
          decidiria não foi feito."
       • "scripts/** não entra em nenhum typecheck do repo: EXIT=0 vacuoso."

     Cobre também: limites declarados do que foi implementado, caminhos que
     ficaram sem teste, e o que foi verificado à mão e não tem regressão. -->

## Gates

<!-- Marque o que se aplica. Escape usado é para declarar, não para esconder —
     todos ficam registrados no event log de qualquer forma. -->

- [ ] Testes e typecheck passaram pelo gate (sem escape)
- [ ] Escape usado: `CANUTO_SKIP_PR_GATE` / `CANUTO_ALLOW_MAIN_PUSH` / `CANUTO_ALLOW_COMMIT` / `--no-verify` — motivo:
- [ ] Delegação/review cruzado: role e veredito
