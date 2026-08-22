---
name: skill-gardener
description: Audita o inventário e uso de skills do Canuto de forma determinística e report-only.
trigger: skill gardener, auditoria de skills, skill-gardener
version: 1.0.0
---

# Skill Gardener

Verifique primeiro o binário instalado:

```bash
~/.canuto/bin/canuto-skill-gardener status --json
```

Use `backfill` uma vez para uma instalação nova e `weekly` nas execuções seguintes. Consulte um resultado com `report --run <id>` e confira `cron status` antes de qualquer decisão operacional.

O auditor é estritamente report-only: não cria, instala, atualiza, arquiva ou remove skills, não escreve nos projetos observados e nunca instala cron automaticamente. Qualquer criação/eval é interativa em `_incubando`, via `skill-creator`, após revisão humana.
