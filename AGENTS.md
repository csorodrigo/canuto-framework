# Project Rules (Codex)

## Context
- Framework: Canuto v1.x at .agents/
- Read .context.md files in each directory for local context
- Read docs/FEATURE-MAP.md for feature status and flows
- Read .agents/tmp/context-package.md if it exists (pre-loaded context from Architect)

## Coding Rules
- Follow existing patterns in nearby files — match style, naming, structure
- Do NOT add new dependencies without explicit instruction in the prompt
- Include basic happy-path tests for new functions
- Use TypeScript strict mode if tsconfig.json has strict: true
- Prefer editing existing files over creating new ones
- Do NOT add comments, docstrings, or type annotations to code you didn't change

## MCP Tools Available
- **obsidian-vault**: Read/write vault notes at ~/.canuto/vault/ for project memory
- **ast-grep**: Structural code search — use for finding patterns, symbols, callers
- **playwright**: Browser automation — navigate, click, fill, screenshot, assert

## Vault Access (Fallback)
If MCP tools are not available, use the vault-bridge shell script:
```bash
bash .agents/tools/vault-bridge.sh read <note-path>
bash .agents/tools/vault-bridge.sh search <query>
```

## File Conventions
- New files follow the naming pattern of existing files in the same directory
- Imports use the project's alias paths (check tsconfig.json or package.json)
- Test files go next to source files or in the nearest tests/ directory

## Codex Profiles

Available profiles in `~/.codex/config.toml` — use when spawned with `--profile`:

| Profile | Model | Reasoning | Use For |
|---------|-------|-----------|---------|
| `coder` | gpt-5.4 | high | Standard code generation |
| `maestro` | gpt-5.4 | xhigh | Direct Codex runtime orchestration |
| `reviewer` | gpt-5.4 | high | Deep code review, security audit |
| `architect` | gpt-5.4 | xhigh | Architecture, complex reasoning |
| `fast` | gpt-5.4 | high | Quick edits, formatting, docs |

- Claude sessions keep Claude Opus as Maestro.
- Direct Codex sessions should use `bash .agents/tools/codex-maestro.sh` or `codex --profile maestro`.

## Anti-Patterns
- Do NOT create README.md, documentation files, or CHANGELOG entries
- Do NOT refactor unrelated code
- Do NOT install packages or modify lock files
- Do NOT modify .env files or configuration
