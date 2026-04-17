---
skill: context-digest
trigger: On session start, or when Architect needs context for planning
persona: contextualizer
version: 1.0.0
lastUpdated: 2026-03-30
shortDescription: >
  Generates compact digests (~50 lines) of source directories. Opus reads digests
  instead of raw files — 10x token savings. Stored in vault at digests/.
usedBy: [contextualizer, architect, maestro]
evals:
  - prompt: "generate context digests for the src directory"
    should_trigger: true
  - prompt: "summarize the codebase for planning"
    should_trigger: true
  - prompt: "read src/auth/middleware.ts"
    should_trigger: false
---

## Purpose

Raw source files are expensive for Opus to read (500 lines = ~1500 tokens).
Digests compress a directory into ~50 lines of essential information.
Opus plans from digests. Codex receives digests in context packages.

**10x token savings per file read.**

## Who generates the digest?

**Primary: Gemini** (`gemini-3.1-pro-preview`) — long-context `@folder` makes this
the cheapest path. Flow:

```
mcp__gemini__ask-gemini({
  prompt: "@src/auth/ Produce a digest in the format specified at
           .agents/skills/context-digest.md (Public API, Key Types, Dependencies,
           Invariants, Gotchas, 5-line summary). Output markdown only.",
  model: "gemini-3.1-pro-preview"
})
→ write the returned markdown to .agents/vault/digests/{slug}.md
```

**Fallback: Codex** via `mcp__codex-coder__spawn_agent` with a context-preload pointing
at the target directory. Use when Gemini quota is exhausted or the repo has auth-sensitive
files that should not cross provider boundaries.

**Never use Opus** to generate digests — that defeats the economy.

Gemini gotchas: serialize calls (stdio single-connection), copy files into the workspace
before `@` (sandbox blocks `/tmp`), and avoid `gemini-2.5-pro` (banned per POC).
See `.agents/skills/gemini-routing.md`.

---

## Digest Format

```markdown
# Digest: src/auth/

**Last updated**: 2026-03-30T14:30:00
**Git hash**: a1b2c3d (matches current HEAD)
**Files**: 8 files, 1,247 LOC total

## Public API
- `createAuthMiddleware(config: AuthConfig): Middleware`
- `validateToken(token: string): Promise<TokenPayload>`
- `refreshSession(sessionId: string): Promise<Session>`

## Key Types
- `AuthConfig { provider: 'jwt' | 'session'; secret: string; expiresIn: number }`
- `TokenPayload { userId: string; role: Role; exp: number }`
- `Session { id: string; userId: string; createdAt: Date; expiresAt: Date }`

## Dependencies
- `jsonwebtoken` (token signing/verification)
- `@supabase/supabase-js` (session storage)
- Internal: `src/models/user.ts`, `src/config/env.ts`

## Architecture
- Middleware pattern: Express-compatible, wraps req.user
- Session storage: Supabase auth.sessions table
- Token flow: JWT signed → cookie → validate on each request

## Summary
Authentication middleware using JWT tokens stored in HTTP-only cookies.
Sessions backed by Supabase. Supports role-based access control.
```

---

## Procedure

### 1. Check Freshness

For each directory being worked on:
```
vault/digests/{dir-hash}.md exists?
  → YES: check git hash matches HEAD
    → MATCH: digest is fresh, use it
    → MISMATCH: regenerate
  → NO: generate new digest
```

### 2. Generate Digest

Read the directory and extract:
1. **File list** with LOC counts
2. **Public API** — exported functions, classes, components (signatures only)
3. **Key types** — interfaces, types, enums used across files
4. **Dependencies** — external packages + internal imports
5. **Architecture** — patterns used (middleware, repository, hooks, etc.)
6. **3-line summary** — what this directory does in plain language

**DO NOT include**: implementation details, function bodies, comments, tests.

### 3. Store in Vault

Save to: `.agents/vault/digests/{dir-hash}.md`
- `dir-hash` = sanitized directory path (e.g., `src-auth` for `src/auth/`)
- Include git hash in frontmatter for freshness checks

### 4. Use in Planning

Architect reads digests instead of raw files:
```
[Reading digest for src/auth/ — 50 lines vs 1,247 lines raw]
```

Only fall back to raw files when:
- Digest is stale (git hash mismatch)
- Planning requires line-level detail (rare)
- Debugging a specific function (use Read tool directly)

---

## Integration Points

- **Architect persona**: reads digests first for planning context
- **Context preload skill**: includes digests in context packages for Codex
- **Cost routing skill**: references digests as the preferred context source
- **Session start**: Contextualizer checks/regenerates stale digests

---

## Anti-Patterns

- DO NOT generate digests for every directory — only directories relevant to current work
- DO NOT include function bodies or implementation details
- DO NOT generate digests for node_modules, .git, or build output
- DO NOT read raw files when a fresh digest exists — defeats the purpose
