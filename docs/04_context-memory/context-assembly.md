# Context Assembly

## Purpose
Define deterministic context compilation from policy, memory, history, tools, skills, and standing-order directives.

## Scope
In scope:
- planning and section budgeting
- retrieval and reduction ordering
- render contract for loop consumption

Out of scope:
- UI prompt rendering
- persistence implementation internals

## Responsibilities
- build auditable `ContextPlan` per request.
- retrieve context sources in deterministic order.
- reduce content to fit budget without hiding critical sections.
- emit `CompiledContextPackage` with trace metadata.

## Core Concepts
- plan-first assembly (`plan → retrieve → reduce → render`).
- section budgets are explicit and enforceable.
- degraded retrieval modes are represented, never silent.

## Core Data Models
### ContextPlan
Required fields:
- `mode`
- `tokenBudget`
- `sectionBudgets`
- `toolExposurePlan`
- `memoryRetrievalPlan`
- `historyPlan`
- `skillPlan`
- `standingOrderPlan`

### CompiledContextPackage
Required fields:
- `sections`
- `estimatedTokens`
- `appliedReductions`
- `auditTrace`

## State Transitions
Pipeline:
`plan → retrieve → reduce → render → consume → post_turn_persist`

Failure branch:
`retrieve|reduce|render → degraded_mode|fail`

## Execution Flow
1. Build `ContextPlan` from mode and policy.
2. Retrieve sources in order:
   - runtime/system directives
   - tool exposure context
   - skill injections
   - memory candidates
   - history windows
   - standing-order directives
3. Reduce by priority:
   - stale tool outputs
   - oversized history segments
   - low-priority memory/context blocks
4. Render final package with section accounting.
5. Hand package to loop.
6. Trigger post-turn memory candidate formation.

## Failure Modes
- source retrieval failure → degraded package with explicit source marker.
- token overrun after reduction → fail request with budget reason.
- render failure → fail with structured context error.

## Constraints
- critical policy/system sections cannot be silently dropped.
- reduction must preserve auditability.
- context assembly decisions must be reproducible from traces.

## Invariants
- each package has one audit trace id.
- retrieval ordering is deterministic for same inputs.

## Observability
- section budget planned vs actual
- retrieval source counts and latency
- reductions applied and token deltas
- degraded-mode markers

## Related Documents
- [Compaction Strategy](./compaction-strategy.md)
- [Memory Architecture](./memory-architecture.md)
- [Standing Orders](../06_triggers-automation/standing-orders.md)

## Open Questions
- final ranking and tie-break strategy for memory candidates under tight budgets.
