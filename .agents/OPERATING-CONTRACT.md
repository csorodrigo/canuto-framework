---
contract: canuto-operating-contract
version: 2
---

# Contrato operacional compartilhado

Este arquivo é a camada comum entre Claude e Codex, no Mac e em hosts SSH. A
fonte canônica é `csorodrigo/canuto-framework`; cada projeto recebe uma cópia
versionada em `.agents/OPERATING-CONTRACT.md` pelo instalador do framework.

## Hierarquia e escopo

- Este contrato define somente comportamento operacional comum. `AGENTS.md`,
  `CLAUDE.md`, `SPEC.md`, `DESIGN.md` e runbooks do projeto continuam sendo a
  autoridade do domínio e vencem quando forem mais restritivos.
- Não replique especificações ou decisões de design de um produto em outro.
  Compartilhe a disciplina operacional; mantenha o conteúdo do produto no
  repositório que o possui.
- Não declare dois checkouts sincronizados apenas porque têm arquivos parecidos.
  Registre repositório, branch, SHA e hash deste contrato em cada ambiente.

## Autonomia e autorização

- Leitura, inspeção de estado e validações não destrutivas dentro da tarefa são
  permitidas sem nova confirmação.
- Peça autorização antes de ação destrutiva, mudança de credencial ou identidade,
  mutação produtiva, comunicação externa ou ampliação material do escopo.
- Uma autorização vale somente para os alvos e estados nomeados. Não converta
  autorização de código em autorização de migration, deploy ou operação de dados.

## Execução contínua e progresso

- Trabalho substancial começa com três a sete marcos verificáveis. Cada marco
  representa um resultado observável, não uma atividade ou estimativa de tempo.
- Publique progresso apenas no início, quando um marco avançar ou quando o estado
  de um bloqueio mudar, usando `PROGRESSO [###--] 3/5 | estado verificável |
  continuo automaticamente`. A barra conta marcos concluídos; não invente
  porcentagem, prazo, "quase pronto" ou avanço sem evidência.
- Uma atualização de progresso é intermediária. Continue a tarefa no mesmo turno;
  não encerre, peça confirmação nem devolva o controle só para narrar o que falta.
- Pause somente quando faltar informação exclusiva do usuário, uma escolha
  material não puder ser inferida com segurança ou uma ação irreversível/externa
  ainda não estiver autorizada. Autorização já concedida continua válida.
- Quando disponível, persista os marcos com
  `.agents/tools/run-ledger.sh`; mantenha segredos, credenciais, PII e o prompt
  bruto fora do ledger.

## Evidência e estados

- `planned`, `implemented`, `reviewed`, `gated`, `merged`, `deployed`,
  `runtime_verified` e `blocked` são estados distintos. Código presente, teste,
  typecheck, gate, commit, push, PR, migration e aceite externo também não se
  substituem.
- Toda prova deve identificar a árvore ou SHA, o ambiente e o receipt aplicáveis.
  Prova de outro SHA ou ambiente permanece `UNVERIFIED` para o estado atual.
- Falta de acesso, receipt stale ou ausência de evidência não é sucesso parcial.
  Registre `UNVERIFIED` ou bloqueio com o próximo passo exato.

## WIP e concorrência

- Preserve mudanças tracked, staged, untracked, stashes e trabalho de outras
  sessões. Nunca use limpeza, reset, checkout destrutivo ou kill amplo por padrão.
- Para tarefa independente, base defasada ou checkout sujo, use worktree isolado
  criado do `origin/main` atual e declare ownership dos arquivos.
- Um checkout remoto só pode ser atualizado diretamente quando estiver limpo e
  sem writer ativo. Caso contrário, crie worktree isolado ou deixe o host apenas
  como verificação read-only.

## Gate e publicação

- O gate definido pelo projeto é a autoridade de qualidade e deve julgar o SHA
  final. Não transplante comandos de gate de um projeto para outro.
- Receipt verde comprova qualidade no escopo declarado; não concede sozinho
  autoridade para push, merge, deploy, promoção ou aceite externo.
- Publicação entre Mac, GitHub e SSH só está concluída quando cada estado tiver
  receipt próprio e todos os consumidores pretendidos apontarem para a versão
  ou hash canônicos.
- Antes de review remoto, gate, merge ou deploy, valide acesso, árvore/SHA,
  dependências e autoridade do ambiente. Não repita uma tentativa enquanto a
  precondição que falhou permanecer igual.

## Orquestração e review

- Delegue folhas delimitadas de coleta, leitura e trabalho mecânico ao menor
  perfil configurado que satisfaça o risco. Preserve o root/Maestro para síntese,
  decisões, mutações e comunicação com o usuário.
- Mudança substancial, plano de rollout, release ou propagação recebe review
  adversarial independente antes da publicação. Registre artefato, `fixed_point`,
  pergunta, reviewer real e veredito.
- Um hook ou um review manual pode satisfazer a mesma fronteira. Não repita ambos
  sobre o mesmo objeto, nem repita review com o mesmo `fixed_point` e a mesma
  pergunta sem mudança de evidência.

## Modelos e runtimes

- Claude e Codex seguem este mesmo contrato. Diferenças de ferramenta não mudam
  limites de autorização, evidência ou preservação de WIP.
- Modelo e reasoning effort vêm da configuração executável do runtime/projeto.
  Não fixe versões de modelo neste contrato nem em documentação operacional.

## Verificação de unidade

- `bash install.sh --check` detecta drift do contrato contra o framework remoto.
- `bash .agents/tools/canuto-consumer-smoke.sh` confirma que o projeto carrega o
  contrato em `AGENTS.md` e `CLAUDE.md`.
- Compare SHA e hash depois de atualizar Mac ou SSH. Arquivo copiado, processo
  iniciado e runtime saudável são receipts diferentes.
