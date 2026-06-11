# Personas Aposentadas

`tester.md` e `debugger.md` movidas para cá em **2026-06-11** — auditoria de 200 sessões
mostrou que nenhuma tinha caminho real de invocação: perdem para as skills `/test` e `/fix`
e para o `codex exec`, que escreve os testes no mesmo spawn do Coder.

Fluxo novo: **Maestro → Architect → [Co-Review se M/L] → Coder (implementa + testes) → Reviewer**.
Debugging/test-failure segue o fluxo `/fix` (regras de fingerprint), não uma persona dedicada.

Para restaurar: `git mv .agents/personas/_archive/<nome>.md .agents/personas/<nome>.md`.
