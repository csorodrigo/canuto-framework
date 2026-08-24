---
name: canuto-ptbr-editor
description: >
  Escreve ou revisa automaticamente artefatos editoriais em português brasileiro,
  preservando fatos, autoria, modalidade, incerteza e tokens técnicos literais.
  Use para documentação, handoffs, relatórios, e-mails, texto de produto, ajuda,
  resumos editados e tradução para PT-BR. Não use apenas porque a conversa está
  em português, nem para código, comandos, dados, citações ou transcrição literal.
metadata:
  canuto-type: "global-skill"
  canuto-version: "0.1.0"
  canuto-updated: "2026-08-24"
  canuto-invocation: "model"
  canuto-runtimes: "claude,codex"
  source-revision: "rafaelquintanilha/skills@8c4991b"
  provenance: "Implementação clean-room; nenhum texto upstream foi copiado porque o repositório não declarava licença."
---

# Editor PT-BR do Canuto

Produza o artefato pedido em português brasileiro natural. Esta skill é um
padrão editorial, não uma persona conversacional e não um perfil de marca.

## Confirme o contrato do artefato

Antes de redigir, identifique:

- finalidade, público, formato e limite de espaço;
- registro e tom solicitados;
- fatos obrigatórios e relações entre eles;
- trechos que precisam permanecer literais;
- incertezas, aprovações e pendências que não podem ser resolvidas por estilo.

Infira lacunas conservadoramente. Se uma convenção, nome ou afirmação depender
de uma fonte disponível, consulte-a. Se a fonte não puder ser verificada, não
invente a informação ausente.

## Preserve o significado

- Mantenha fatos, autoria, responsabilidade, cronologia, escopo e grau de certeza.
- Não transforme “pode” em “deve”, observação em recomendação, plano em execução,
  teste em deploy ou ausência de prova em conclusão.
- Preserve literalmente comandos, caminhos, variáveis, identificadores, nomes de
  API, mensagens de erro e outros tokens protegidos, salvo pedido explícito.
- Em tradução, reconstrua a frase em sintaxe portuguesa; não replique a ordem de
  palavras do inglês nem faça substituição mecânica de sinônimos.
- Use o termo técnico corrente quando a tradução reduzir precisão. Integre-o à
  frase com artigos, preposições, gênero e número naturais em português.

## Ajuste ao tipo de artefato

Para botão, label, título ou mensagem curta:

- prefira ação ou estado inequívoco;
- descreva apenas a causa conhecida;
- ofereça somente uma recuperação que realmente exista;
- respeite o espaço disponível sem fundir ideias diferentes.

Para texto com frases completas, leia
[a revisão editorial](references/review-checklist.md) antes de finalizar.

O perfil de voz do produto continua sendo a autoridade para informalidade,
persuasão, emojis, urgência e formatação de canal. Não transforme WhatsApp em
comunicado corporativo nem documentação técnica em publicidade.

Retorne apenas o artefato final, salvo se o usuário pedir comparação, opções ou
justificativa editorial.
