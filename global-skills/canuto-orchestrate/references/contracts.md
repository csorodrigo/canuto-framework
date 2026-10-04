# Contratos de delegação

## Entrada mínima da folha

```text
TASK_ID
ROLE
EXECUTOR
MODEL_REQUESTED
ACCESS_POLICY
OBJECTIVE
QUESTION
READ_SET
DESTINATION
FORBIDDEN_SET
SOURCE_OF_TRUTH
CONSTRAINTS
EVIDENCE_STANDARD
RETURN_SCHEMA
MUTATION_POLICY: read-only
DELEGATION_POLICY: leaf-never-delegate
STOP_CONDITION
CAPACITY_EVIDENCE
```

Declare caminhos e sistemas concretos. `READ_SET` não concede acesso fora da
tarefa; `FORBIDDEN_SET` registra superfícies que não devem ser consultadas ou
alteradas. `DESTINATION` identifica o artefato de retorno, não concede escrita
à folha. O wrapper pode capturar a resposta fora da área lida. A folha deve
parar quando faltar fonte, autorização ou isolamento.

## Retorno mínimo da folha

```text
STATUS
EXECUTION_STATUS
TASK_ID
QUESTION_ANSWERED
SCOPE_INSPECTED
EVIDENCE
MODEL_REQUESTED
MODEL_CONFIGURED
MODEL_EFFECTIVE
MODEL_EVIDENCE
ATTEMPTS
PARTIAL_ARTIFACT
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

O root classifica o retorno como completo, parcial, conflitante ou rejeitado.
Conclusão do executor exige status de sucesso e artefato não vazio; isso não
comprova correção do conteúdo. Identidade ausente fica `UNVERIFIED`. Recusa,
timeout, saída vazia e modelo indisponível permanecem estados distintos.
