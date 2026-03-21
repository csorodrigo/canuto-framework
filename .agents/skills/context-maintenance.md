shortDescription: How to maintain .context.md, FEATURE-MAP.md, and the Repo Index (evaluate-repo pipeline) as the project evolves.
usedBy: [contextualizer, coder, architect, maestro]
version: 2.0.0
lastUpdated: 2026-03-08
copyright: Rodrigo Canuto © 2026.

## When to Use

**Triggers:**
- A directory's purpose, structure, or responsibility has changed
- Files, components, or dependencies were added or removed
- A new user-facing feature was created or significantly altered
- Coder or Architect needs to decide whether `.context.md` needs updating after a change

**Not for:**
- Bug fixes that don't change architecture or directory structure
- Style, formatting, or test-only changes
- Internal refactors that preserve the same external structure

---

## Purpose

Every meaningful directory in a project should have a `.context.md` that orients whoever arrives next — human or agent.

The project also keeps a single `docs/FEATURE-MAP.md`, a feature index that maps every user-facing feature to the code path that implements it.

Together, `.context.md` answers **"what lives here?"** and the feature map answers **"how does this feature work, end-to-end?"**.

This skill defines **when** to update these files, **how** to keep them accurate, and **how to behave when the project uses a different schema**.

---

## Scan Rules

- Start from `src/` as the root. Most projects keep source code there.
- Skip hidden and tooling directories: `.git`, `.idea`, `.vscode`, `.cache`, `dist`, `build`, `node_modules`, `venv`, `__pycache__`, `.next`, `.turbo`.
- A directory is "meaningful" if it has 2+ source files or represents a clear domain boundary.

---

## .context.md

### When to Update

An update is **required** when a change alters:
- The purpose or responsibility of a directory.
- The addition or removal of files, components, or dependencies.
- Naming conventions or structural patterns within the directory.

An update is **NOT required** for:
- Bug fixes that do not change architecture.
- Style or formatting-only changes.
- Internal refactors that preserve the same external behavior and structure.
- Adding or modifying files that fit the existing documented pattern.

### Schema Detection

- If the file starts with a `<context …>` tag, `Summary`, `Constraints`, and `Guidance` sections → **Canuto schema**.
- If the file uses another recognizable structure → **foreign schema**.

**Behavior:**
- On Canuto schema: keep and enforce the structure below.
- On foreign schema: do NOT rewrite the structure. Update content in the same style.

### Canuto .context.md Schema

```markdown
<context path="relative/path" updated="YYYY-MM-DD">

One to two sentences describing what this directory contains and why it exists.

## Summary

- filename.ext – short description of what this file does.
- otherfile.ext – short description of what this file does.
- subdirectory/ – short description of what this subdirectory contains.

## Constraints

- MUST / MUST NOT statements. Non-negotiable constraints specific to this directory.

## Guidance

- SHOULD / SHOULD NOT statements. Recommendations that may be deviated from with justification.

</context>
```

**Schema rules:**
- The `<context>` tag carries the relative path and a last-updated date.
- The description is prose, not a list. Answer "what is here" and "why does it exist".
- Summary covers every file and subdirectory. One line each.
- Constraints and Guidance are optional — only include when the directory has rules worth stating.
- Use RFC-style language (MUST, SHOULD, MUST NOT, SHOULD NOT).
- Keep it short. This file is read frequently by multiple personas.
- The `.context.md` update MUST be in the same commit as the code change it documents.

---

## docs/FEATURE-MAP.md

### When to Update

An update is **required** when a change:
- Adds, removes, or renames a user-facing feature.
- Alters the information flow of an existing feature.
- Moves or renames files that appear in an existing feature path.

An update is **NOT required** for:
- Bug fixes that do not change the flow.
- Internal refactors that preserve the same entry points and layers.
- Style, formatting, or test-only changes.

### Schema Detection

- If the file has sections per feature with Flow lists of paths → **Canuto schema**.
- If the file uses another style (tables, other headings) → **foreign schema**. Extend using its own pattern.

### Canuto FEATURE-MAP.md Schema

```markdown
# Feature Map

Auto-maintained index of every user-facing feature and the code path that implements it.
Updated alongside the code — not after the fact.

---

## [Feature Name]

Brief description of what this feature does from the user's perspective.

**Flow:**

1. `path/to/entry_point.ext` – what happens here (e.g., route handler, CLI command).
2. `path/to/service.ext` – what happens here (e.g., validation, orchestration).
3. `path/to/repository.ext` – what happens here (e.g., persistence, external calls).
4. `path/to/presenter.ext` – what happens here (e.g., response formatting).
```

**Schema rules:**
- One section per feature.
- The feature name is the user-visible name, not an internal module name.
- The flow lists files in the order information travels — from entry point to final output.
- Each step is a file path plus a short phrase describing that file's role.
- Keep descriptions to one line.
- If a feature branches (e.g., sync vs async), show the primary path and note the branch.
- The feature map update MUST be in the same commit as the feature code changes.

---

## Evaluate Repo — Deep Indexation Pipeline

A 4-stage pipeline inspired by AI knowledge-base systems. Produces a comprehensive, searchable index of the entire repository. Runs during bootstrap or on demand.

**Output files:**
- `docs/REPO-INDEX.md` — human-readable domain map with entities, tags, and relationships.
- `~/.canuto/vault/projects/{project-slug}/repo-index.json` — machine-readable index for programmatic queries by personas.

Together with `.context.md` (per-directory) and `FEATURE-MAP.md` (per-feature), the Repo Index answers **"what entities exist, how are they related, and where do I find them?"**.

### When to Run

- **Bootstrap**: First session on a new project — run after generating `.context.md` and `FEATURE-MAP.md`.
- **On demand**: User explicitly requests `evaluate-repo` or Maestro detects significant structural changes (new modules, renamed directories, major refactors).
- **Periodic refresh**: When `repo-index.json` is older than 7 days and significant commits have landed.

**NOT for:**
- Minor bug fixes or style changes.
- Projects with fewer than 10 source files (`.context.md` + `FEATURE-MAP.md` are sufficient).

### Stage 1 — Entity Extraction

Scan every meaningful source file and extract:

| Entity Type | What to Extract |
|-------------|-----------------|
| `function` | Exported/public functions with signature summary |
| `class` | Classes with key methods listed |
| `component` | UI components (React, Vue, Svelte, etc.) |
| `route` | API routes/endpoints with method and path |
| `middleware` | Express/Koa/Fastify middleware |
| `schema` | Database schemas, Zod/Yup validations, TypeScript interfaces |
| `hook` | Custom hooks (React useX, Vue composables) |
| `service` | Service classes/modules (business logic orchestrators) |
| `config` | Configuration files with key settings |
| `type` | Exported TypeScript types/interfaces that define contracts |

**Rules:**
- Skip internal/private helpers unless they are critical to understanding the domain.
- Record file path and line number for each entity.
- Use the function/class name as-is — do not rename or abbreviate.

### Stage 2 — Dependency Analysis

For each extracted entity, map:

1. **Imports**: What does this entity depend on? (other entities, external libraries)
2. **Dependents**: What depends on this entity? (reverse lookup)
3. **External dependencies**: Which npm/pip/cargo packages does this entity use directly?

**Output per entity:**
- `dependencies`: list of entity names or `external:<package>` references.
- `dependents`: list of entity names that import/call this entity.

**Rules:**
- Only map direct dependencies (1 level deep). Do not recurse transitively.
- Mark external dependencies with the `external:` prefix (e.g., `external:zod`, `external:express`).
- If a dependency cannot be resolved, tag it as `[UNCERTAIN]`.

### Stage 3 — Semantic Tagging

For each entity, generate 3–8 searchable tags from these categories:

| Tag Category | Examples |
|--------------|----------|
| **domain** | `auth`, `payments`, `notifications`, `onboarding`, `dashboard` |
| **layer** | `controller`, `service`, `repository`, `middleware`, `ui`, `hook`, `util` |
| **pattern** | `singleton`, `factory`, `observer`, `pub-sub`, `middleware-chain`, `HOC` |
| **tech** | `react`, `express`, `prisma`, `zod`, `redis`, `stripe`, `supabase` |
| **concern** | `validation`, `error-handling`, `caching`, `rate-limiting`, `logging` |

**Rules:**
- Tags are lowercase, hyphenated (e.g., `error-handling`, not `Error Handling`).
- Prefer specific over generic: `jwt-validation` is better than `validation`.
- Do not invent tags — only tag what is observable in the code.

### Stage 4 — Categorization

Group all entities into **domains** with confidence scores:

1. **Identify domains**: Analyze tags and directory structure to discover natural domain boundaries (e.g., `Authentication`, `Payments`, `User Management`, `Dashboard`).
2. **Assign entities**: Each entity belongs to 1–2 domains. If ambiguous, assign to the most relevant and note the secondary.
3. **Score confidence**: Rate each domain assignment:
   - `0.9–1.0` — Entity clearly belongs here (file path + tags agree).
   - `0.7–0.89` — Likely belongs here (tags match, path is ambiguous).
   - `0.5–0.69` — Uncertain (cross-cutting concern, could belong elsewhere).
4. **Map cross-domain dependencies**: Note which domains depend on which (e.g., `Payments → Authentication`).

### Repo Index Schemas

#### docs/REPO-INDEX.md (Canuto Schema)

```markdown
# Repo Index

> Auto-generated deep index of the repository. Maps every significant entity, its tags, relationships, and domain.
> Generated by the Evaluate Repo pipeline. Updated alongside major structural changes.

**Stats:** X entities | Y domains | generated YYYY-MM-DD

---

## Domain: [Domain Name] [confidence: X.XX]

[1-2 sentences describing what this domain covers]

**Tags:** tag1, tag2, tag3

| Entity | Type | File | Line | Tags |
|--------|------|------|------|------|
| entityName | function | path/to/file.ts | 15 | tag1, tag2 |
| OtherEntity | class | path/to/other.ts | 8 | tag3, tag4 |

**Dependencies → other domains:**
- → [Other Domain] (reason: entity X calls entity Y)

---

## Cross-Domain Map

| Domain | Depends On | Depended By |
|--------|-----------|-------------|
| Authentication | Config, Database | Payments, Dashboard |
| Payments | Authentication, Database | — |
```

#### ~/.canuto/vault/projects/{project-slug}/repo-index.json (Canuto Schema)

```json
{
  "version": "1.0.0",
  "generated": "YYYY-MM-DD",
  "stats": {
    "entityCount": 47,
    "domainCount": 6,
    "tagCount": 82
  },
  "domains": [
    {
      "name": "Authentication",
      "confidence": 0.95,
      "description": "Handles JWT generation, validation, and session management.",
      "tags": ["auth", "jwt", "session", "middleware"],
      "entities": [
        {
          "name": "generateToken",
          "type": "function",
          "file": "src/auth/token-service.ts",
          "line": 15,
          "tags": ["jwt", "generation", "auth"],
          "dependencies": ["external:jsonwebtoken", "config.jwtSecret"],
          "dependents": ["authMiddleware", "refreshSession"]
        }
      ],
      "domainDependencies": ["Config", "Database"],
      "domainDependents": ["Payments", "Dashboard"]
    }
  ],
  "crossDomainMap": [
    {
      "from": "Payments",
      "to": "Authentication",
      "reason": "verifyPaymentSession calls authMiddleware"
    }
  ]
}
```

### Procedure

1. **Run Stage 1** (Entity Extraction): Scan all source directories. Produce raw entity list.
2. **Run Stage 2** (Dependency Analysis): For each entity, resolve imports and dependents.
3. **Run Stage 3** (Semantic Tagging): Tag each entity with 3–8 tags.
4. **Run Stage 4** (Categorization): Group into domains, assign confidence, map cross-domain dependencies.
5. **Generate outputs**: Write `docs/REPO-INDEX.md` and `~/.canuto/vault/projects/{project-slug}/repo-index.json`.
6. **Present summary to user**:
   ```
   Evaluate Repo complete:
   - X entities extracted across Y files
   - Z domains identified: [list]
   - Top cross-domain dependencies: [list]

   Approve and save? (or request changes)
   ```
7. **Save only after user approval.**

### How Personas Use the Repo Index

| Persona | Usage |
|---------|-------|
| **Maestro** | Reads `repo-index.json` to understand project scope and route tasks to the right domain expert. |
| **Architect** | Consults domain map and cross-domain dependencies before designing new features. Avoids creating redundant entities. |
| **Coder** | Searches entities by tag to find existing code before writing new code. Prevents duplication. |
| **Reviewer** | Validates that new code fits the domain boundaries. Flags cross-domain violations. |
| **Contextualizer** | Uses as input when updating `.context.md` — ensures consistency between context files and the index. |

---

## Examples

### ✅ Good — complete, useful .context.md

```markdown
<context path="src/auth" updated="2026-03-01">

Handles all authentication logic: JWT generation, validation, and session refresh.
This directory owns the auth contract — no other directory should duplicate token logic.

## Summary

- token-service.ts – generates and verifies JWTs using the configured secret.
- auth-middleware.ts – Express middleware that attaches decoded user to req.user.
- session-store.ts – manages refresh token persistence via Redis.

## Constraints

- MUST NOT store tokens in localStorage — use httpOnly cookies only.
- MUST throw InvalidTokenError (never return null) on verification failure.

## Guidance

- SHOULD use short-lived access tokens (15min) with long-lived refresh tokens (7d).

</context>
```

Orients the next agent instantly: what lives here, what the rules are, what each file does.

### ❌ Bad — vague, useless .context.md

```markdown
# Auth

This folder contains authentication files.
```

This is bad because: tells the agent nothing specific, doesn't list files, has no constraints or guidance — the next agent will read the raw source code anyway, defeating the purpose.

### ✅ Good — rich, searchable repo-index.json entity

```json
{
  "name": "authMiddleware",
  "type": "middleware",
  "file": "src/auth/middleware.ts",
  "line": 8,
  "tags": ["auth", "express", "guard", "jwt-validation"],
  "dependencies": ["external:express", "generateToken", "config.jwtSecret"],
  "dependents": ["createPayment", "getUserProfile", "updateSettings"]
}
```

Precise location, specific tags, clear dependency chain. Any persona can find this instantly.

### ❌ Bad — vague, untagged entity

```json
{
  "name": "middleware",
  "type": "function",
  "file": "src/auth/middleware.ts",
  "line": 1,
  "tags": ["middleware"],
  "dependencies": [],
  "dependents": []
}
```

This is bad because: generic name, no line precision, single vague tag, no dependencies mapped — provides no more value than reading the raw file.

---

## Guardrails

- Never invent purpose. If a directory's role is unclear, say so.
- Never add a feature to the map that you cannot trace end-to-end. If the path is unclear, say so.
- Never update the `updated` date in a `.context.md` unless the content actually changed.
- On non-standard projects: detect the existing schema, adapt to it, never overwrite with Canuto schema without explicit user instruction.
- Never assign a domain confidence above 0.9 unless both file path and tags clearly agree.
- Never generate a repo index for projects under 10 source files — `.context.md` and `FEATURE-MAP.md` are sufficient.
- Never tag entities with generic-only tags. At least 2 tags must be domain-specific.
- Always present the repo index summary to the user before saving. Never auto-save.
