# Session Lifecycle

## Purpose
Define deterministic projection from run/execution state into session-visible UI and interaction state.

## Scope
In scope:
- session state machine
- run transition to UI mapping
- suspended/frozen/failure projection behavior

Out of scope:
- widget rendering details
- storage engine implementation

## Responsibilities
- project execution lifecycle into user-visible session states.
- preserve resumability metadata for suspended runs.
- expose failure/frozen reasons without ambiguity.

## Core Concepts
- session state is a projection layer, not the source of lifecycle truth.
- projection must follow `ExecutionResult.visibilityContract`.
- projection failures do not mutate persisted terminal run status.

## Session State Machine
`idle → processing → waiting_confirmation|waiting_input|waiting_event → suspended → resumed → processing → terminal`

Terminal states:
- `completed`
- `failed`
- `frozen`
- `cancelled`

## Projection Mapping
| Run transition | Session state | Required projection |
|---|---|---|
| `created/queued` | processing | queue/running indicator with request metadata |
| `running → waiting_for_confirmation` | waiting_confirmation | pending approval state with correlation id |
| `running → waiting_input` | waiting_input | explicit input-required prompt |
| `running → waiting_event` | waiting_event | external wait marker |
| `suspended` | suspended | resumable marker + waiting reason |
| `completed` | completed | final response and completion metadata |
| `failed` | failed | structured error reason/code |
| `frozen` | frozen | blocked/no-progress terminal marker |
| `cancelled` | cancelled | cancellation reason and source |

## Execution Flow
1. Receive run transition or terminal result event.
2. Resolve session-state mapping.
3. Apply visibility contract branch (`chat_visible|state_only|both`).
4. Persist session projection event.
5. Emit UI update event.

## Failure Modes
- projection write failure: log projection error and retry; run terminal state remains authoritative.
- missing correlation ids: project degraded status with explicit observability marker.
- conflicting projections from stale events: reject stale update by sequence ordering.

## Constraints
- session projection cannot invent lifecycle states not in execution model.
- terminal session states are immutable unless superseded by a new request.

## Invariants
- every terminal run event yields one terminal session projection event.
- suspended session must carry resume identifiers.

## Observability
- projection event id, request/run correlation
- source transition and mapped session state
- projection success/failure and retry count

## Related Documents
- [Execution Model](../02_system/execution-model.md)
- [Execution Policy](../02_system/execution-policy.md)

## Open Questions
- final ordering semantics for cross-device/session replay scenarios.
