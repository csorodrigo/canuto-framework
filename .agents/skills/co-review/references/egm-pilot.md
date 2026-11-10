# Pilotos EGM: compreensão e divergência entre documento e código

Opt-in, dentro da contagem do co-review. Referência: google/elephant-goldfish-model
`8f168124593f26ce4125361f5e3ec9a073ebf174`. Os prompts abaixo são adaptações locais;
não instalam o toolkit nem importam o loop de cinco rodadas/duas rodadas limpas.

## Preparação e qualificação

Congele as fontes e registre hash dos bytes, versão do prompt, pergunta e limite
de chamadas. Use um documento limpo e um com defeito conhecido; não entregue o
gabarito ao revisor. Compare uma chamada do review habitual com uma da lente
especializada, usando os mesmos casos e modelo configurado, em conversas novas.
Não acrescente contexto-package, vault, conversa do autor ou resultados anteriores.

| Adapter | Configuração | O que ainda exige prova |
| --- | --- | --- |
| Agente nativo Codex | `fork_turns="none"`, tarefa explícita | instruções do host, memória e acesso a arquivos |
| Codex CLI do hook | cwd externo, read-only, ephemeral, stdin | host AGENTS/config, memória e restrição de leitura |
| Claude blind-reviewer | Read/Grep/Glob, contexto novo | filesystem continua legível; herança de CLAUDE.md |

No Claude que expõe `omitClaudeMd: true` (EGM documenta CLI >=2.1.271), configure
no adapter e faça probe nativo antes de alegar exclusão. Não adicione um campo
não suportado ao frontmatter da persona. Políticas gerenciadas podem permanecer.
EGM #237 documenta vazamento de instruções de host no Codex: contexto novo não
é garantia global. Um canário ausente só prova ausência daquele canário no probe.

## Prompt: compreensão

```text
Leia somente os documentos anexados. Não use ferramentas ou fontes externas.
Para cada caso: explique "O que propõe" e "Como funciona segundo o documento".
Liste termos próprios do projeto sem definição e decisões cuja interpretação
mudaria a implementação. Cite a frase e a consequência. Não cobre definição de
termos técnicos gerais nem invente requisito. Se não houver problema, diga isso.
Não tente corrigir o documento. Fontes ausentes permanecem não avaliadas.
```

Esta lente avalia se a spec se explica. Restrições do código/ADRs continuam com a
revisão técnica existente. Paths concretos ficam no plano de execução versionado;
não imponha paths à spec durável do `to-spec`.

## Prompt: divergência semântica

```text
Compare apenas os pares de documento/código anexados. Cada documento declara
accepted, proposed ou historical. Somente accepted pode contradizer o contrato
vigente. Proposta não entregue e história anterior não são bugs de drift.
Aponte afirmação, trecho de código, cenário e efeito observável de cada divergência.
Com fonte insuficiente, reporte não avaliado. Detalhe interno não documentado,
sozinho, não é divergência. Não execute testes ou consulte outros arquivos.
```

## Medição e decisão

Registre por execução: hash do corpus e prompt, adapter/versão, modelo pedido e
efetivo (ou UNVERIFIED), fontes e limitações, chamadas, bytes, duração, conclusão
ou NAO_AVALIADO. Julgue achados contra o gabarito: úteis adicionais, falsos
positivos e omissões. Tokens/custo só entram quando medidos pelo runtime.

Adote uma lente automática apenas com ganho útil sobre o review habitual e
custo/ruído aceitáveis demonstrados. Resultado equivalente mantém opt-in;
resultado inferior recomenda descartar ou ajustar. Um corpus pequeno não prova
qualidade geral. Fonte inacessível/execução interrompida não conta como caso limpo.
Não executar pilotos no preflight determinístico ou disparar rodadas até ficar verde.
