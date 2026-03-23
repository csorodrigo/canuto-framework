---
skill: skill-creator
trigger: /skill-creator
persona: maestro
version: 1.0.0
lastUpdated: 2026-03-23
shortDescription: Create or improve a Canuto Framework skill — captures intent, defines structure, writes the SKILL.md, defines evals, and integrates into the vault.
usedBy: [maestro]
evals:
  - prompt: "i want to create a new skill for automating db migrations in our project"
    should_trigger: true
  - prompt: "the commit skill isnt working well, want to improve it"
    should_trigger: true
  - prompt: "the commit skill is throwing an error, help me debug it"
    should_trigger: false
  - prompt: "how do i use the experiment-loop skill?"
    should_trigger: false
---

## When to Use

**Triggers:**
- User wants to create a new skill from scratch: "create a skill for X", "add a skill that does Y"
- User wants to improve an existing skill: "the X skill isn't working well", "update the Y skill to also do Z"
- User wants to add `evals` to an existing skill

**Not for:**
- Debugging why a skill isn't triggering (that's `/investigate`)
- Running an existing skill (just invoke it directly)
- Creating Obsidian vault templates (that's part of `knowledge-ingest`)

---

## Purpose

Standardize how new skills enter the Canuto Framework. Ensures every skill is correctly structured, has a trigger-accurate `shortDescription`, follows Progressive Disclosure (≤200 lines body), and has `evals` for validation.

Adapted from the Anthropic skill-creator methodology to work within Canuto's persona orchestration model.

---

## Workflow

| Phase | Persona | Action |
|---|---|---|
| **1. Intent** | Maestro | Interview: what does it do, when does it trigger, what's the output |
| **2. Research** | Maestro | Check if similar skill exists; read related skills for conventions |
| **3. Structure** | Architect | Define frontmatter, sections, progressive disclosure level (flat vs directory) |
| **4. Write** | Coder | Write SKILL.md following template and quality checklist |
| **5. Evals** | Tester | Define 4 eval prompts (2 should-trigger, 2 near-miss should-not-trigger) |
| **6. Review** | Reviewer | Validate shortDescription, body length, evals quality, handoff clarity |
| **7. Integrate** | Maestro | Register in vault as decision if architectural; update health-check if critical |

For XS skills (simple new workflow, clear scope): skip Architect phase, Maestro owns structure.

---

## Phase 1: Intent Interview

Ask the user:

1. **What should this skill enable?** (concrete task, not abstract goal)
2. **When should it trigger?** List 3–5 realistic user phrases that should invoke it
3. **When should it NOT trigger?** List 2–3 near-miss phrases that look similar but shouldn't invoke it
4. **What's the expected output?** (file created, decision made, report generated, etc.)
5. **Which persona executes it?** (Maestro orchestrates, or does a specific persona implement?)

Do not proceed to Phase 2 until you have clear answers to all 5.

---

## Phase 2: Research

Before drafting:

- `ls .agents/skills/` — check for existing skills with similar names or purposes
- Read 1–2 most similar skills to understand conventions and avoid overlap
- Check `SPEC.md § 4` to understand skill taxonomy (Core, Advanced, Plugin)

If a similar skill already covers 80%+ of the intent, consider extending it instead of creating a new one.

---

## Phase 3: Structure Decision

Choose the right structure based on expected body size:

| Expected size | Structure |
|---|---|
| ≤200 lines | Single `skill-name.md` flat file |
| >200 lines | `skill-name/SKILL.md` + `skill-name/references/` directory |

For directory-based skills, decide which sections go in `references/` vs the body:
- **Body**: When to Use, Purpose, Procedure overview, Guardrails
- **References**: Large example sets, code recipes, per-variant details, heavy checklists

---

## Phase 4: Writing the SKILL.md

### Frontmatter template

```
---                               # use --- delimiters (YAML block)
skill: skill-name
trigger: /skill-name
persona: maestro
version: 1.0.0
lastUpdated: YYYY-MM-DD
shortDescription: >
  [What it does] — [when to use it]. Include key trigger phrases.
usedBy: [persona1, persona2]
evals:
  - prompt: "realistic user phrase with context"
    should_trigger: true
  - prompt: "edge case that also should trigger"
    should_trigger: true
  - prompt: "near-miss: same domain, different intent"
    should_trigger: false
  - prompt: "another near-miss: shared keywords, different need"
    should_trigger: false
---
```

### Required sections

```markdown
## When to Use
**Triggers:** (3–5 specific phrases/scenarios)
**Not for:** (2–3 anti-patterns to prevent over-triggering)

## Purpose
1–3 sentences: what problem this solves and why it exists as a skill.

## [Core content]
The actual procedure, workflow, checklist, or decision tree.

## Guardrails
What this skill must never do.
```

### Writing principles (from skill-creator methodology)

- **Explain the why**, not just the what — LLMs have good theory of mind and respond better to reasoning than rigid MUST/NEVER rules
- **Generalize from examples** — don't write instructions that only work for the test cases you imagined; write for the category
- **Keep it lean** — remove anything not pulling its weight; verbose prompts generate verbose, unfocused outputs
- **One high-impact instruction beats five weak ones**

---

## Phase 5: Writing Evals

Good evals test the real boundary between "use this skill" and "don't use this skill".

**For `should_trigger: true`:**
- 1 obvious case: user clearly wants this skill
- 1 edge case: user needs this skill but doesn't name it explicitly

**For `should_trigger: false`:**
- Both must be near-misses — prompts that share keywords or domain but need a *different* skill or no skill at all
- Avoid obviously irrelevant prompts — they don't test anything

**Format prompts realistically:**
- Include context (project background, what the user was doing)
- Allow typos, casual speech, incomplete sentences
- Be specific (mention file names, technologies, situations)

---

## Phase 6: Review Checklist

Before finalizing:

- [ ] `shortDescription` accurately describes when to trigger — not too broad, not too narrow
- [ ] Body is ≤200 lines (or split into directory if longer)
- [ ] 4 evals defined: 2 should-trigger, 2 near-miss should-not-trigger
- [ ] `Not for` section has at least 2 entries preventing common over-triggering scenarios
- [ ] Skill doesn't duplicate an existing skill (checked in Phase 2)
- [ ] Persona assignment is correct — Maestro for orchestration, specific personas for implementation
- [ ] Instructions explain the *why*, not just the what

---

## Phase 7: Integration

After the skill is written and reviewed:

1. **Place the file** in `.agents/skills/` (flat `.md` or `skill-name/` directory)
2. **If the skill is critical** (frequently triggered, core workflow): add to the critical list in `health-check.md`
3. **If the skill represents an architectural decision**: create a `D-XXX` decision note in the vault
4. **If an existing skill was modified**: bump `version` field and update `lastUpdated`
5. **Announce to user**: brief summary of what was created, the trigger command, and the evals

---

## Guardrails

- Do not create a skill before completing the intent interview — incorrect assumptions lead to rework
- Do not create a new skill if an existing one covers 80%+ of the intent — extend instead
- Do not write skills with MUST/NEVER in all-caps unless you've tried explaining the reasoning first
- Do not overfit instructions to specific examples — write for the general category
