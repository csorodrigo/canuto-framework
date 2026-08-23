# ADR-0017 — Stable por padrão, edge explícito e source receipt

Data: 2026-08-23 · Status: aceito

## Contexto

O instalador e o update multi-projeto baixavam diretamente de `main`. Um merge
recém-publicado podia alcançar vários consumidores antes de canário e, como
versão textual e source ref eram estados comprimidos, dois conteúdos distintos
podiam parecer igualmente atualizados.

## Decisão

- `stable` é o canal padrão; `edge` resolve explicitamente para `main`.
- `--version X` resolve para `releases/X`; `--ref` aceita pin exato.
- `--rollback X` é update explícito a partir de `releases/X`.
- O bootstrap remove os seletores da argv do instalador filho e propaga o
  endpoint/ref por ambiente, mantendo compatibilidade com instaladores antigos.
- Install/update completos gravam `.agents/SOURCE-RECEIPT.json` de forma
  atômica e determinística, com source ref, versão e digest SHA-256 do manifesto.
- `update-all` compara versão e receipt; source divergente não é `OK`.
- URL customizada continua suportada, mas não pode ser combinada com seletor
  CLI porque isso produziria provenance ambígua.

## Consequências

- (+) `main` deixa de ser rollout implícito.
- (+) pin e rollback não dependem do estado atual de `main`.
- (+) provenance fica verificável e idempotente.
- (-) a branch `stable` e os refs `releases/*` passam a exigir promoção
  deliberada depois dos receipts de CI/canário.
