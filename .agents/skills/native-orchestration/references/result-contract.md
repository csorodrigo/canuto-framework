# Native Orchestration Result Contract

All native leaves return the following shape in plain Markdown.

```text
STATUS: COMPLETE | PARTIAL | BLOCKED | CONTRACT_VIOLATION
TASK_ID: <assignment identifier>
ROLE: <agent role>
QUESTION_ANSWERED: <yes | partial | no>

SCOPE_INSPECTED
- <exact paths, artifacts, or sources inspected>

EVIDENCE
- <claim> — <file:line, command/output reference, or authoritative artifact>

FINDINGS
- [severity or confidence] <finding>

ABSENCES
- <what was searched for and not found>

UNCERTAINTIES
- <what remains unknown and why>

OUTBOUND_FLAGS
- <adjacent issue not investigated, or none>

RECOMMENDED_NEXT_CHECK
- <smallest discriminating check, or none>

MUTATIONS
- none

DELEGATION
- none
```

## Root Acceptance Checks

Reject or downgrade a result when:

- `MUTATIONS` is not `none`;
- `DELEGATION` is not `none`;
- a finding has no evidence trace;
- the leaf inspected outside its `READ_SET` without stopping;
- a reviewer claims tests passed without authoritative command output;
- a reviewer claims live state such as merged, deployed, or published;
- a Spec review lacks the original request or approved plan;
- uncertainty is hidden behind confident language.

A `COMPLETE` result can still be wrong. The root must compare it with the source of
truth and remains responsible for the final conclusion.
