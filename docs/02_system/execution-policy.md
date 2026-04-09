# Execution Policy

## Purpose
Define default runtime behavior for duplicates, queueing, retries, timeouts, suspend/resume legality, and completion visibility.

## Core Data Models
`ExecutionPolicy` minimum fields:
- `allowToolUse`, `allowPersistence`, `allowSuspend`
- `maxSteps`, `maxToolCalls`, `timeoutMs`
- `duplicatePolicy`: `allow|reject|replace_running|coalesce|queue`
- `queuePolicy`: `fifo|priority|none_reject`
- `retryPolicy`: `none|fixed(maxRetries, backoffMs)`
- `failurePolicy`: `fail_run|freeze_run`
- `completionPolicy`: `emit_chat_response|state_only|both`

## Source-Type Default Policy Semantics
| Source type | Mode default | Duplicate default | Queue default | Retry default | Timeout profile | Completion default |
|---|---|---|---|---|---|---|
| chat_user | `ephemeral_request` | `reject` | `none_reject` | `none` | interactive/short | `emit_chat_response` |
| trigger.schedule/interval | `triggered_request` | `queue` | `fifo` | `fixed` | background/medium | `both` |
| trigger.mcp_event (bursty) | `triggered_request` | `coalesce` | `fifo` | `fixed` | background/short-medium | `both` |
| resume_signal | `resume_request` | `reject` | `priority` | `none` | inherited from run policy | `both` |
| manual system action | `persistent_request` | `queue` | `priority` | `fixed` | medium-long | `both` |

> Exact numeric constants remain decision items; this table defines semantic defaults.

## Suspend/Resume Legality Grid
| Condition | Suspend legal? | Resume legal? | Notes |
|---|---|---|---|
| `allowSuspend=false` | No | No | Suspend request must fail/freeze per policy. |
| Ephemeral mode | No | No | No durable run lifecycle. |
| Persistent mode + waiting state | Yes | Yes | Requires persisted `RunState`. |
| Triggered mode without durable run | No | No | Must create persistent run first. |
| Terminal run state | No | No | Terminal states are non-resumable. |

## Responsibilities
- Executor enforces policy legality.
- Loop consumes policy limits; it does not redefine policies.
- Trigger arbitration applies policy-consistent pre-execution decisions.

## Constraints
- Duplicate/concurrency outcomes must be explicit and recorded.
- Retry behavior must be bounded.
- Completion visibility must map deterministically to session projection.

## Observability
Record policy snapshot/hash, enforcement branch chosen, and any override source.

## Open Questions
- Final numeric defaults by source class (queue bounds, retries, timeout durations).
- Final priority ordering among trigger classes.

## Related Documents
- [Execution Model](./execution-model.md)
- [Trigger Lifecycle](../06_triggers-automation/trigger-lifecycle.md)
