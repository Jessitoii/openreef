# Memory Write Discipline

## Purpose
Define strict acceptance criteria for memory writes and prevent low-reliability long-term persistence.

## Scope
In scope:
- candidate evaluation
- long-term vs short-term write rules
- rejection behavior and observability

Out of scope:
- memory retrieval ranking

## Responsibilities
- evaluate `MemoryWriteCandidate` reliability and importance.
- route candidates to `long_term|short_term|drop`.
- preserve explainable write/reject decisions.

## Core Concepts
- long-term writes are privilege-gated.
- failed/error-heavy turns are write-conservative.
- duplicate suppression is mandatory before durable writes.

## Core Data Models
### MemoryWriteCandidate
- `candidateId`
- `fact`
- `importance`
- `sourceTurnId`
- `reliabilityFlags`
- `writeDisposition` (`long_term|short_term|drop`)

### WriteDecision
- `candidateId`
- `decision`
- `reasonCodes[]`
- `writtenRecordRef?`
- `timestamp`

## State Transitions
`candidate_extracted → evaluated → accepted_long_term|accepted_short_term|dropped`

## Execution Flow
1. Extract candidates post-turn.
2. Evaluate reliability flags and turn health.
3. Run duplicate suppression.
4. Apply importance threshold.
5. Commit to selected store or drop with reason.

## Acceptance Rules
Long-term write requires all:
- terminal turn success
- no unresolved critical tool failure impacting fact trust
- importance ≥ threshold
- duplicate suppression pass
- parse integrity pass

Short-term-only path:
- ambiguous facts
- insufficient confidence
- useful transient context

Drop path:
- malformed extraction
- low importance + low confidence
- unresolved contradictory evidence

## Failure Modes
- candidate parse failure → drop with parse error reason.
- duplicate checker unavailable → disable long-term writes and use short-term/drop policy.
- store write failure → emit failed decision and retry policy marker.

## Constraints
- no long-term writes from failed/frozen runs unless explicit override policy exists.
- write decisions must be explicit and auditable.

## Invariants
- every candidate gets exactly one decision record.
- reason code set cannot be empty for drop/failure outcomes.

## Observability
- accepted/rejected counts by disposition
- top rejection reasons
- duplicate suppression hit rate
- long-term write latency/failure counts

## Related Documents
- [Memory Architecture](./memory-architecture.md)
- [Context Assembly](./context-assembly.md)

## Open Questions
- final threshold calibration strategy by domain/task class.
