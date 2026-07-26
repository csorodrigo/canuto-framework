# Plugins arquivados (2026-07-26)

`ccb`, `notebooklm`, `example-ci-status` — o mecanismo de descoberta descrito
em `plugin-system` ("Maestro detects the plugin on session start") nunca foi
implementado: nenhum persona, hook ou CLAUDE.md menciona plugins, e nenhum
plugin estava em FRAMEWORK_FILES. Capacidade nunca invocável.

Para restaurar um plugin: `git mv` de volta para `.agents/plugins/<name>/` e
implementar a descoberta (referência no session-start.sh ou CLAUDE.md).
