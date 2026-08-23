---
name: continuous-learning
description: Extract reusable project instincts from session outcomes and reinforce them over time.
shortDescription: Extract, store, and evolve reusable patterns (instincts) from session experience.
usedBy: [maestro, reviewer, coder]
version: 1.4.0
lastUpdated: 2026-08-23
copyright: Rodrigo Canuto © 2026.
evals:
  - prompt: "session is ending, extract any instincts from what we learned today"
    should_trigger: true
  - prompt: "we fixed the same bug 3 times now, lets document this pattern so it doesnt happen again"
    should_trigger: true
  - prompt: "how many instincts do we have in the vault?"
    should_trigger: false
  - prompt: "the coder keeps making the same mistake, review its last output"
    should_trigger: false
---

## When to Use

**Triggers:**
- At session end — Maestro extracts instincts from the session's decisions, rework, and patterns
- User says: `"what did we learn?"`, `"show instincts"`, `"evolve"`, `"what patterns have we found?"`
- After a Reviewer REQUEST CHANGES — extract the "why" as a preventive instinct
- After a /fix diagnosis — extract the root cause pattern as a diagnostic instinct

**Not for:**
- Generic knowledge already covered by skills
- One-off decisions that belong in `decisions.md` (e.g., "chose JWT over sessions")

---

## Purpose

Capture project-specific patterns that emerge from real development sessions. Unlike skills (generic, reusable across projects) and decisions (one-time choices), **instincts** are learned behaviors specific to THIS project that improve agent performance over time.

Instincts bridge the gap between "what the framework knows" (skills) and "what this project needs" (experience).

---

## Concepts

### Instinct

A reusable pattern learned from experience. Each approved instinct has:

| Field | Description |
|-------|-------------|
| **ID** | Auto-incrementing (`I-001`, `I-002`, ...) |
| **Pattern** | What was observed (the trigger/situation) |
| **Learning** | What to do about it (the action/response) |
| **Confidence** | `low` (approved first occurrence) → `medium` (2-3) → `high` (4+) |
| **Category** | `code-pattern`, `architecture`, `testing`, `workflow`, `debugging`, `design` |
| **Applied** | Count of times this instinct influenced a decision |

### Two Tiers (v1.4 — mechanical candidate boundary)

A memória tem dois tiers com regras de escrita **diferentes**:

| Tier | O que é | Escrita |
|---|---|---|
| **Hipótese** | `memory-candidates/`, session notes, pending e metrics | **Automática e reversível.** Memória extraída é colocada em quarentena como `proposed + low`; não entra em `instincts/`, `decisions/` nem no briefing ativo. |
| **Curado** | `instincts/`, promoções a `medium`/`high`, decisions, regras em `stack.md`, global instincts | **Só com aprovação humana explícita.** Carrega autoridade e é exento de aging automático de candidatos. |

A fronteira é executável em `.agents/tools/vault-sync.sh`:

- aceita somente schema `canuto-memory-candidate/v1`;
- exige `tier: hypothesis`, `authority: memory`, `status: proposed` e `confidence: low`;
- exige projeto, sessão e evidência de origem;
- grava somente em `memory-candidates/` ou `pending-sync/` quando offline;
- rejeita campos de aprovação, segredos, projeto divergente e target curado;
- recusa comandos `promote`, `approve` e `curate`.

Isso evita que uma extração automática transforme uma conversa ou resumo em verdade operacional.

### Authority Order

```text
curated decision/skill > approved instinct > memory candidate
```

Um candidato pode sugerir investigação, mas nunca vencer uma decisão, skill, regra ou evidência de projeto já aprovada.

### Confidence Scoring

| Level | Criteria | Behavior |
|-------|----------|----------|
| `low` candidate | First observed occurrence, not approved | Quarantined; never injected automatically |
| `low` approved | Human accepted first occurrence | May be shown as a weak suggestion |
| `medium` | 2-3 approved observations across sessions | Actively recommended by personas |
| `high` | 4+ approved observations or explicit human promotion | Treated as a soft rule |

Confidence never increases because a model repeated the same claim. Each reinforcement needs a new source and human approval before changing curated memory.

### Instinct Lifecycle

```text
Observation → Candidate → Quarantine → Human review → Approved instinct → Reinforcement → Promotion
```

---

## Candidate Storage

Automatically extracted memories are individual notes at:

```text
~/.canuto/vault/projects/{project-slug}/memory-candidates/{candidate-id}.md
```

Required envelope:

```markdown
---
schema: canuto-memory-candidate/v1
type: memory-candidate
id: MC-20260823-001
project: my-project
tier: hypothesis
authority: memory
status: proposed
confidence: low
target-kind: instinct
source-system: canuto
source-session: sessions/2026-08-23
source-evidence: reviewer:MUST-FIX-2
---

# Short candidate title

**Pattern:** What was observed.

**Learning:** What may reduce future mistakes.
```

Allowed `target-kind` values are `instinct`, `session`, `pending`, `metric`, and `audit`. A candidate never chooses its final curated path.

Validate and stage:

```bash
bash .agents/tools/vault-sync.sh validate-candidate /tmp/candidate.md
bash .agents/tools/vault-sync.sh stage-candidate /tmp/candidate.md
```

When the vault is unavailable, the same validated envelope is stored in `pending-sync/`; a later bare `vault-sync.sh` routes it to `memory-candidates/` without changing authority.

---

## Approved Instinct Storage

Only human-approved instincts live at `~/.canuto/vault/projects/{project-slug}/instincts/I-XXX-slug.md`:

```markdown
---
type: instinct
id: I-001
category: code-pattern
confidence: low
applied: 0
source-session: "[[sessions/2026-03-21]]"
last-seen: 2026-03-21
status: active
promoted-to: ""
tags:
  - instinct
  - confidence/low
  - category/code-pattern
---

# [Category] Short title

**Pattern:** When/where this occurs.

**Learning:** What to do about it.

**Source:** [[sessions/2026-03-21]]
```

Query approved instincts via `bases/instincts-by-confidence.base` for grouped views. Candidate notes are deliberately outside that active view.

---

## Procedure

### Extracting Candidates (Session End)

At the end of each session, before writing the closeout:

1. **Scan for real signals:**
   - rework files (count ≥ 3);
   - Reviewer MUST FIX items;
   - root-cause diagnoses from `/fix`;
   - repeated user corrections;
   - measured production or gate failures.

2. **For each signal, search both curated instincts and candidates:**
   - existing candidate: create a new evidence-linked candidate or reference the old one; never overwrite conflicting content;
   - existing approved instinct: create a reinforcement candidate naming the instinct; do not mutate confidence automatically;
   - no match: create a new candidate with `confidence: low`.

3. **Create the candidate envelope** with project slug, source system, source session and a concrete evidence locator. Vague claims without evidence are discarded.

4. **Stage automatically through the mechanical gate:**

   ```bash
   bash .agents/tools/vault-sync.sh stage-candidate /tmp/<candidate>.md
   ```

5. **Report what was staged**, without presenting it as learned truth:

   ```text
   Session memory candidates:
   - [STAGED] MC-20260823-001 — [debugging] Auth middleware swallowed an error
   - [REJECTED] MC-20260823-002 — missing source evidence
   ```

6. **Never write directly to `instincts/`, `decisions/`, `stack.md` or global memory from extraction.**

### Reviewing Candidates

When the user asks to review memory:

1. list `memory-candidates/` separately from `instincts/`;
2. show candidate ID, source system, source session and evidence;
3. compare against existing decisions, skills and instincts;
4. label each candidate: `approve`, `merge`, `reject`, `needs-evidence`;
5. preview the exact curated diff;
6. apply only after explicit human approval;
7. preserve the candidate as provenance, updating its status through the approved promotion workflow rather than deleting it.

### Applying Instincts (During Session)

Personas consult only approved instincts:

- **Architect**: read `high` and `medium` instincts before planning;
- **Coder**: read approved instincts in the relevant category before implementing;
- **Reviewer**: check approved `code-pattern` and `testing` instincts;
- **Fluxo /fix**: read approved `debugging` instincts before investigating.

`memory-candidates/` is not part of automatic recall or briefing. It is review input only.

Format:

```text
[Maestro] Relevant approved instincts for this task:
- I-003 [high] Form validation: always validate on blur, not on submit
- I-011 [medium] Auth flows: check token refresh before API calls
```

### Reviewing Approved Instincts

1. query `instincts/` or `bases/instincts-by-confidence.base`;
2. show applied count, sources and last-seen date;
3. suggest pruning approved instincts not seen in 10+ sessions;
4. suggest promotion only when evidence and usage thresholds are satisfied.

### Promoting Instincts

Promotion remains human-controlled. Read `references/instinct-promotion.md` for preview, approval, provenance and tracking rules.

`vault-sync.sh` intentionally has no promotion capability. The review workflow must create the curated diff and obtain approval before writing.

### Pruning and Aging

Candidate memory can be archived mechanically after its retention window, but never silently promoted. Existing approved-instinct aging remains:

```bash
bash .agents/tools/instinct-aging.sh --dry-run
bash .agents/tools/instinct-aging.sh --apply
```

It never deletes history. Curated `medium/high` instincts remain exempt from automatic pruning.

---

## Guardrails

- Automatic extraction writes only validated candidates to `memory-candidates/`.
- Curated memory always requires explicit human approval and an exact diff preview.
- Candidate authority is always `memory`; it never claims `decision`, `evidence`, `skill`, or `rule` authority.
- Candidates must name a source session and concrete evidence locator.
- A candidate from another project is rejected even when the content is semantically similar.
- Never include secrets, raw tokens, private IDs or full session transcripts.
- Max candidate size is 32 KiB; keep Pattern + Learning concise.
- Never overwrite a different candidate with the same ID.
- Confidence increases only through approved, independently sourced observations.
- Do not duplicate skills; reference the applicable skill instead.
- Instinct IDs are never reused.

→ **Examples** (good/bad instinct extraction, reinforcement): read `references/examples.md`

---

## Bulk Classification

For a large review queue, classification may be delegated read-only, but the result is still a proposal:

```bash
codex exec --color never --profile fast \
  -s read-only --skip-git-repo-check \
  -o /tmp/canuto-classify-$$.md \
  "Classifique cada candidato em {approve, merge, reject, needs-evidence}: <itens>"
```

Bulk classification never grants approval or writes curated memory.
