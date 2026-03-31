---
name: vault-sync
description: Sincroniza artefatos offline de `.agents/.cache/pending-sync/` de volta para o backend ativo do vault ou para a memoria legada.
type: global-skill
version: 1.0.0
lastUpdated: 2026-03-31
copyright: Rodrigo Canuto © 2026
---

# /vault-sync — Offline Memory Sync

Use este comando quando uma sessao terminou sem acesso de escrita ao vault e o framework pediu sincronizacao posterior.

## Quando Usar

- Depois de uma sessao offline
- Quando hooks mencionarem `.agents/.cache/pending-sync/`
- Quando o Obsidian ou MCP voltarem a funcionar e voce quiser consolidar a memoria

## Protocolo

1. Execute:

```bash
bash .agents/tools/vault-sync.sh
```

2. Leia o resumo:
   - `vault-sync complete: X synced, 0 failed.` -> sucesso
   - `No pending sync files to process.` -> nada pendente
   - `No writable memory backend available.` -> rode `bash install.sh --doctor`

3. Se houver falhas, nao apague arquivos manualmente. Corrija o backend e rode novamente.

## Output Esperado

```markdown
## Vault Sync
- Pending items processed: X
- Failed items: Y
- Backend used: global vault | local vault | legacy memory
```
