---
name: implement-spec
description: "Implement a specification in code."
disable-model-invocation: true
version: 1.1.0
lastUpdated: 2026-09-01
---

You have been provided a spec. This spec should have tickets associated with it, describing how to implement the spec.

The goal is a PR which implements the entire spec on a single branch.

The tickets are not a list of steps. They are a **task graph** with blocking relationships between them. This means there is always a **frontier** of tickets which are ready to be grabbed.

Communication to and from subagents should be sparse. Communicate primarily through **context pointers**: to the spec, tickets, research notes, and previous commits. Don't duplicate information already available via pointers.

**Implementer subagents** should be run in the background where possible for **maximum concurrency**.

## Steps

1. Read the spec and tickets. Read enough to understand the task graph.

2. (optional) Use an **exploration subagent** to conduct any exploration required by the tickets - relevant codebase files or external documentation. Ensure the exploration subagent can save files - it should save its markdown notes in a directory outside the repo, accessible by all future subagents. This lets **implementer subagents** focus on implementation rather than exploration.

3. Create a branch, and a draft PR. The PR should be marked as 'closing' the spec issue and tickets.

4. Use **implementer subagents** to implement each ticket. Each implementer subagent should work in its own worktree, on its own branch.

5. Once an **implementer subagent** completes, merge its work to the PR branch with a **merger subagent**.

6. If this changes the **frontier** of available tickets, kick off more **implementer subagents** to work on the new tickets. This allows for maximum concurrency.

7. Before code review, run a spec-to-artifact completeness gate. Map every requirement and ticket to its implementation, tests, and owned operational artifact. When code reads or writes a new database object:

   - verify that the canonical data owner contains the migration and that the delivery includes or pins its exact revision;
   - apply the migration twice to a disposable database and check constraints, indexes, normalization, and least-privilege grants;
   - record `migration authored`, `migration merged`, `migration applied`, and `runtime verified` as separate states with the code SHA and migration digest;
   - if production application was not explicitly authorized, keep the release `HOLD` or `UNVERIFIED` and provide the exact application command. A passing application build does not prove schema availability.

8. Once all tickets and completeness checks are complete, run /code-review on the PR branch. Fix all issues raised by the code review in a single **implementer subagent**.

9. Mark the PR as ready for review.

10. Clean up all **implementer subagent** worktrees.
