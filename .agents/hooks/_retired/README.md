# Hooks aposentados

- plan-review.sh (2026-06-11): 0 firings na auditoria de 200 sessões; o co-review de planos M/L é acionado pelo Maestro via codex-delegate.sh reviewer (skill co-review), não por hook. Restaurar com git mv + re-registrar no settings-snippet.json.

- `cleanup-tmp.sh`, `validate-config.sh` (2026-07-26): zero referências em
  settings-snippet.json, hooks/install.sh, FRAMEWORK_FILES, CI e demais
  arquivos — nunca tiveram caminho de disparo.

- `session-load.sh` (2026-07-28): instalado, validado pelo health-check e citado
  em três documentos — mas **registrado em evento nenhum e chamado por ninguém**.
  Só a metade que grava (`session-save.sh`, no `Stop`) funcionava; a que carrega
  nunca rodou. Ficou seis meses assim sem ninguém sentir falta: o briefing de
  sessão do CLAUDE.md já faz a mesma função de forma seletiva. Manter um hook
  instalado e documentado que nunca executa é pior que qualquer decisão — parece
  uma rede de segurança que não existe.
