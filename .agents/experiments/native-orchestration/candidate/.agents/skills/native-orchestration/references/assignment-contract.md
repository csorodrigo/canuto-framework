# Native Orchestration Assignment Contract

Every native leaf receives a complete, bounded assignment. Omitted fields make the
assignment invalid.

```text
TASK_ID: <stable identifier>
ROLE: canuto_native_scout | canuto_native_reviewer
OBJECTIVE: <one concrete outcome>
QUESTION: <one independently answerable question>
READ_SET:
  - <file, directory, log, diff, plan, or source allowed for inspection>
FORBIDDEN_SET:
  - <paths, systems, or actions outside scope>
SOURCE_OF_TRUTH:
  - <authoritative artifact or explicit statement that none exists>
CONSTRAINTS:
  - read-only
  - no external communication
  - no credentials or identity changes
  - no production mutation
  - no delegation
VALIDATION_OR_EVIDENCE_STANDARD:
  - <what counts as support: file:line, command output, reproducible observation, etc.>
RETURN_SCHEMA: native-result-v1
MUTATION_POLICY: read-only
DELEGATION_POLICY: leaf-never-delegate
STOP_CONDITION: <when the leaf must stop instead of broadening scope>
```

## Assignment Rules

- One assignment asks one primary question.
- `READ_SET` is an allowlist, not a suggestion.
- `FORBIDDEN_SET` includes adjacent areas that are tempting but irrelevant.
- The user request or approved plan must be included verbatim when reviewing Spec.
- Never pass secrets, credentials, unrelated conversation history, or resolved
  exploration into a leaf prompt.
- A missing authoritative source must be stated explicitly; do not manufacture one.
- A leaf that discovers a possible adjacent issue reports it under `OUTBOUND_FLAGS`
  without investigating it further.
