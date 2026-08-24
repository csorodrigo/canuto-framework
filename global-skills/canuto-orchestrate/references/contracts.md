# Contratos de delegação

## Entrada mínima da folha

```text
TASK_ID
ROLE
OBJECTIVE
QUESTION
READ_SET
FORBIDDEN_SET
SOURCE_OF_TRUTH
CONSTRAINTS
EVIDENCE_STANDARD
RETURN_SCHEMA
MUTATION_POLICY: read-only
DELEGATION_POLICY: leaf-never-delegate
STOP_CONDITION
```

Declare caminhos e sistemas concretos. `READ_SET` não concede acesso fora da
tarefa; `FORBIDDEN_SET` registra superfícies que não devem ser consultadas ou
alteradas. A folha deve parar quando faltar fonte, autorização ou isolamento.

## Retorno mínimo da folha

```text
STATUS
TASK_ID
QUESTION_ANSWERED
SCOPE_INSPECTED
EVIDENCE
FINDINGS
ABSENCES
UNCERTAINTIES
RECOMMENDED_NEXT_CHECK
MUTATIONS: none
DELEGATION: none
```

Evidência identifica arquivo, linha, comando, timestamp, SHA, ambiente ou receipt
quando aplicável. Ausência de evidência fica explícita; confiança verbal não a
substitui.
