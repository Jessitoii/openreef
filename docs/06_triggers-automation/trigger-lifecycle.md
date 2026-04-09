# Trigger Lifecycle

## Purpose
Define trigger lifecycle, normalization, and arbitration contract.

## Core Data Models
- `TriggerDefinition`: id, type, binding target, enabled, optional policy override.
- `TriggerEvent`: event id, trigger id, event key, occurred timestamp, payload/source.
- `TriggerArbitrationDecision`: `proceed|queue|reject_duplicate|replace_running|coalesce`.

## State Transitions
`registered → enabled → fired → normalized → arbitrated → dispatched → recorded`

Branch states: `rejected_duplicate|queued|coalesced|replace_running|dispatched`.

## Policy Matrix
| Scenario | Default Decision | Owner Layer |
|---|---|---|
| Same trigger fires during active run, policy reject | reject_duplicate | arbitration + executor |
| Same trigger fires during active run, policy queue | queue | arbitration |
| Same trigger fires during active run, policy replace | replace_running | executor |
| Bursty MCP same key, policy coalesce | coalesce | arbitration |
| Foreground chat active + background trigger | queue (chat priority) | executor |
| Foreground chat active + explicit high-priority replace policy | replace_running | executor |

## Constraints
- Concurrency decisions are owned by arbitration/executor layers.
- Trigger UI cannot directly resolve concurrency conflicts.
