# Trigger Lifecycle

## Purpose
Define trigger lifecycle, event normalization, arbitration semantics, and dispatch rules into unified execution.

## Scope
In scope:
- trigger definitions and event normalization
- arbitration outcomes (dedupe/queue/reject/replace/coalesce)
- dispatch eligibility and recording

Out of scope:
- scheduler timing internals (see trigger scheduler)

## Responsibilities
- normalize trigger events into canonical input objects.
- evaluate standing-order directives.
- apply arbitration decisions before dispatch.
- create `triggered_request` for executor intake.

## Core Concepts
- triggers do not create alternate runtime path.
- arbitration happens before executor dispatch.
- every trigger fire is recorded even when rejected/coalesced.

## Core Data Models
### TriggerDefinition
- `triggerId`, `type`, `bindingTarget`, `enabled`, `policyOverride?`, `standingOrderRefs[]`

### TriggerEvent
- `eventId`, `triggerId`, `eventKey`, `occurredAt`, `payload`, `source`

### TriggerArbitrationDecision
- `proceed|queue|reject_duplicate|replace_running|coalesce`

## State Transitions
`registered → enabled → fired → normalized → arbitrated → dispatched|queued|rejected_duplicate|coalesced|replace_running → recorded`

## Arbitration Policy Matrix
| Scenario | Decision | Owner |
|---|---|---|
| same trigger while run active, policy reject | `reject_duplicate` | arbitration + executor |
| same trigger while run active, policy queue | `queue` | arbitration |
| same trigger while run active, policy replace | `replace_running` | executor |
| bursty MCP events same key, coalesce policy | `coalesce` | arbitration |
| foreground chat active + background trigger | `queue` (default) | executor policy |
| explicit high-priority replace policy | `replace_running` | executor policy |

## Execution Flow
1. Trigger fire event received.
2. Event normalized to `TriggerEvent`.
3. Standing-order directives evaluated.
4. Arbitration decision selected.
5. Dispatch branch creates `ExecutionRequest(mode=triggered_request)` when allowed.
6. Outcome and branch recorded.

## Failure Modes
- malformed event payload → reject with validation reason.
- missing binding target → reject and disable trigger pending repair.
- arbitration conflict with no legal branch → reject with conflict reason.

## Constraints
- trigger execution must route through executor.
- arbitration decisions must be explicit and logged.

## Invariants
- each fired event receives one arbitration outcome.
- coalesced events preserve source event references.

## Observability
- fire count by trigger type
- arbitration branch distribution
- queue latency
- dispatch success/failure rates

## Related Documents
- [Trigger Scheduler](./trigger-scheduler.md)
- [Standing Orders](./standing-orders.md)
- [Execution Policy](../02_system/execution-policy.md)

## Open Questions
- default arbitration behavior for mixed-priority trigger bursts across different bindings.
