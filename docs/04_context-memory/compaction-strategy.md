# Compaction Strategy

## Purpose
Define compaction levels, invocation conditions, and safe fallback behavior when context exceeds target budgets.

## Scope
In scope:
- compaction levels and triggers
- fallback behavior
- failure semantics

Out of scope:
- LLM prompt authoring details

## Responsibilities
- reduce token usage while preserving critical sections.
- bound retry behavior.
- expose compaction outcomes for auditability.

## Core Concepts
- levels: `micro`, `auto`, `full`.
- compaction is budget control, not semantic authority.
- fallback behavior must remain deterministic.

## Core Data Models
### CompactionRequest
- `requestId`
- `targetBudget`
- `currentEstimate`
- `allowedLevels`
- `criticalSections`

### CompactionResult
- `level` (`micro|auto|full`)
- `status` (`applied|skipped|failed_fallback_applied|failed`)
- `tokenDelta`
- `retainedCriticalSections`

## State Transitions
`not_needed → micro|auto|full → applied`

`auto|full → failed_fallback_applied|failed`

## Execution Flow
1. Evaluate budget overflow magnitude.
2. Select minimum sufficient level.
3. Apply compaction and recalculate estimate.
4. Escalate level if still above budget and level allowed.
5. If compaction component fails, apply deterministic fallback summary path.
6. If still over budget after allowed attempts, fail with explicit reason.

## Failure Modes
- compaction engine failure → fallback path.
- fallback cannot satisfy critical section retention + budget → fail.
- repeated compaction loops beyond max attempts → fail.

## Constraints
- critical sections defined by policy cannot be dropped.
- compaction retries are bounded.
- compaction must annotate data loss risk markers when aggressive.

## Invariants
- each compaction attempt produces one result record.
- final status must be explicit (`applied|failed_fallback_applied|failed|skipped`).

## Observability
- level chosen and escalation path
- token deltas per attempt
- fallback invocation count
- final over/under-budget result

## Related Documents
- [Context Assembly](./context-assembly.md)
- [Memory Write Discipline](./memory-write-discipline.md)

## Open Questions
- thresholds that trigger each compaction level by model class.
