# Hooks aposentados

- plan-review.sh (2026-06-11): 0 firings na auditoria de 200 sessões; o co-review de planos M/L é acionado pelo Maestro via codex-delegate.sh reviewer (skill co-review), não por hook. Restaurar com git mv + re-registrar no settings-snippet.json.

- `cleanup-tmp.sh`, `validate-config.sh` (2026-07-26): zero referências em
  settings-snippet.json, hooks/install.sh, FRAMEWORK_FILES, CI e demais
  arquivos — nunca tiveram caminho de disparo.
