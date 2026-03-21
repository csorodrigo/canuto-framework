# Canuto Plugin Registry

Plugins estendem o framework com skills, integrações e automações adicionais.

---

## Como Instalar um Plugin

```bash
# Copie a pasta do plugin para .agents/plugins/
cp -r /path/to/plugin .agents/plugins/

# Verifique com health check
# O Maestro detecta plugins automaticamente no session start
```

## Como Criar um Plugin

Veja `.agents/plugins/example-ci-status/` como referência.

### Estrutura

```
.agents/plugins/meu-plugin/
├── plugin.md          # Manifest (obrigatório)
└── skills/
    └── minha-skill.md # Skills do plugin
```

### Manifest (`plugin.md`)

```yaml
---
name: meu-plugin
version: 1.0.0
description: O que o plugin faz
author: seu-nome
requires:              # Skills do core que o plugin precisa
  - audit-trail
compatible: ">=1.6.0"  # Versão mínima do Canuto
---
```

### Regras

1. Plugins **NÃO podem** modificar arquivos do core (`.agents/personas/`, `.agents/skills/`)
2. Se uma skill do plugin conflita com o core, use namespace: `plugin-name:skill-name`
3. O Maestro detecta plugins em `session start` e lista suas skills disponíveis

---

## Plugins Oficiais

| Plugin | Versão | Descrição | Compatível |
|--------|--------|-----------|------------|
| `example-ci-status` | 1.0.0 | Verifica status de CI/CD (GitHub Actions, GitLab CI) | ≥1.6.0 |

## Plugins da Comunidade

| Plugin | Autor | Descrição | Compatível |
|--------|-------|-----------|------------|
| — | — | Contribua com o primeiro plugin da comunidade! | — |

---

## Contribuindo

Para adicionar seu plugin ao registry:

1. Crie o plugin seguindo a estrutura acima
2. Teste com `/health-check` para verificar que não quebra o framework
3. Abra um PR adicionando a entrada na tabela de "Plugins da Comunidade"
