---
contract: canuto-operating-contract
version: 1
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

## Evidência e estados

- Código presente, teste, typecheck, gate, commit, push, PR, merge, migration,
  deploy, runtime ativo e aceite externo são estados distintos.
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
