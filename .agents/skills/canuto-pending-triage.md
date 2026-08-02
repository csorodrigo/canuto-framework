shortDescription: Deduplicate, classify, and prioritize pending tasks across project memory and Canuto vault notes.
usedBy: [maestro, architect, reviewer]
version: 1.1.0
lastUpdated: 2026-08-01
copyright: Rodrigo Canuto © 2026.

## Purpose

Keep pending tasks useful. A pending file that only grows becomes noise. This skill turns accumulated pending items into a short backlog with duplicates removed, owners or next actions clarified, and stale items marked for archive.

---

## Addressable Convention (pending/ and rework/ — anti evaporation-by-omission, eoc ADR-0007)

`<vault>/pending/` and `<vault>/rework/` notes are **addressable items**, not a
blob that gets silently rewritten every triage pass. Frontmatter contract:

```yaml
id: <slug-estável>            # derivado do conteúdo — não muda entre triagens
status: proposed | set | dropped
created: <ISO8601Z>
dropped-reason: <razão>       # OBRIGATÓRIO quando status: dropped, senão vazio
```

- **`proposed`** — entrada permissiva. Toda pendência nasce aqui, incluindo as
  criadas automaticamente pelo hook `session-save.sh` a partir de um
  Next-Entrypoint acionável ou de uma admissão de retrabalho ("redescobri",
  "de novo", "já estava na memória", "refiz") na nota canônica da sessão
  (P2 #9, eoc ADR-0009/0012). O funil de curadoria se aplica à promoção, não
  à entrada — não recuse um item na porta por parecer cru.
- **`set`** — curadoria explícita (esta skill, ou um humano) promoveu o item:
  ainda relevante, redigido com clareza, dono/próxima ação claros.
- **`dropped`** — o item foi encerrado deliberadamente. **`dropped-reason`
  é obrigatório e não pode ser vazio.** Um item sem razão não pode ser
  marcado como dropped.

**Um pending ou rework NUNCA é deletado.** "Arquivar" significa reescrever o
frontmatter para `status: dropped` com a razão — o arquivo permanece no
diretório, legível e auditável. Evaporar por omissão (o item simplesmente
para de aparecer porque uma triagem esqueceu de repeti-lo) é o bug que esta
convenção existe para matar, não um efeito colateral aceitável do "manter a
lista curta".

---

## Inputs

- `.agents/memory/pending.md` (layout legado, quando o backend for `legacy`)
- `.agents/memory/last-session.md`
- `.agents/memory/decisions.md`
- Canuto vault `pending/` notes (ver Addressable Convention acima) — inclui
  entradas `status: proposed` auto-criadas pelo `session-save.sh`
- Canuto vault `rework/` notes (mesmo formato endereçável) — admissões de
  retrabalho destiladas automaticamente da nota de sessão
- user goals for the current session
- current project status from `canuto-project-doctor`

---

## Triage Categories

| Category | Meaning | Action |
|----------|---------|--------|
| `keep-now` | Still relevant and actionable this week | keep near top; promote to `status: set` when curated |
| `dedupe` | Same task appears multiple times | merge into one item (keep the addressable `id` with the strongest evidence; drop the rest with `dropped-reason: duplicate-of <id>`) |
| `convert-decision` | Pending item is really a decision gap | move/propose to decisions; drop the pending with `dropped-reason: converted-to-decision` |
| `convert-instinct` | Pending item is a reusable lesson | propose as instinct; drop the pending with `dropped-reason: converted-to-instinct` |
| `blocked` | Needs user/external dependency | mark blocker explicitly; stays `status: proposed` or `set`, never dropped just for being blocked |
| `archive` | stale, obsolete, or already done | **never delete** — rewrite frontmatter to `status: dropped` with a non-empty `dropped-reason`; the file stays in `pending/` or `rework/` |

---

## Procedure

1. Read pending sources (see Inputs — includes `status: proposed` items auto-created by `session-save.sh`).
2. Normalize each item into one action sentence.
3. Group duplicates by project area, file path, feature, or intent.
4. Assign each group a triage category.
5. Keep a maximum of 10 active (`proposed` or `set`) pending items surfaced in the summary unless the user asks for full backlog — `dropped` items are excluded from the count but never removed from disk.
6. Produce a proposed diff: for each item, the target `status` transition (`proposed → set`, `proposed → dropped`, or unchanged) and, for any drop, the exact `dropped-reason`.
7. Ask for approval before writing any `status` change — promotion to `set` and drop-with-reason both require approval (ADR-0007: the funnel applies to curation, not to entry). Never delete a pending/rework file.

---

## Output Format

```markdown
## Pending Triage

### Active Pending
- [ ] <task> — source: <file/line or note>

### Duplicates To Merge
- <canonical task>
  - duplicate: <old wording/source>

### Convert
- Decision: <item> -> <decision note>
- Instinct: <item> -> <candidate instinct>

### Drop Candidates (status: proposed|set -> dropped)
- <id> — dropped-reason: <stale|obsolete|done|duplicate-of X|converted-to-decision|converted-to-instinct>

### Proposed Next Action
<one practical next step>
```

---

## Guardrails

- **Never delete a pending or rework file.** The only way to retire an item is `status: dropped` + a non-empty `dropped-reason`, written after approval. A `status: dropped` note with no reason is invalid — treat it the same as a missing drop.
- Never rewrite pending/rework memory (including status transitions) without approval.
- Auto-created entries (`source: session-save`, `tags: [auto-distilled]`) start as `status: proposed` — triage them like any other proposed item; being auto-created is not itself a reason to drop.
- Do not keep broad goals as pending tasks.
- Preserve source traceability when merging duplicates (point the surviving item's body at the dropped duplicate's `id`).
- Prefer fewer, sharper tasks over complete but unusable backlog dumps — "fewer" means fewer surfaced as active, not fewer files on disk.
